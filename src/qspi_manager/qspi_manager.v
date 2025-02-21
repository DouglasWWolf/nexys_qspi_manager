


// We want the QSPI interface signals broken out for debug
`define ADD_DEBUG_PORTS

// Tell "qspi_fields.vh" that we are a receiver of QSPI requests
`define QSPI_FRONT_END

// Fetch the lengths of the QSPI related fields
`include "qspi_field_widths.vh"

module qspi_manager #
(
    parameter FREQ_HZ   = 100000000,
    parameter QSPI_FREQ =  50000000    
)  
(
    input clk, resetn,

    // Broken out fields for debugging
    `ifdef ADD_DEBUG_PORTS
        output [  `QSPI_CMD_LEN-1:0] dbg_qspi_cmd,  
        output [ `QSPI_ADDR_LEN-1:0] dbg_qspi_addr, 
        output [`QSPI_WDATA_LEN-1:0] dbg_qspi_wdata,
        output [`QSPI_START_LEN-1:0] dbg_qspi_start,
        output [`QSPI_RDATA_LEN-1:0] dbg_qspi_rdata, 
        output [ `QSPI_IDLE_LEN-1:0] dbg_qspi_idle,
    `endif

    // The QSPI request and response interface parameterss
    input [`QSPI_REQ_WIDTH-1:0] qspi_req_in,
    output[`QSPI_RSP_WIDTH-1:0] qspi_rsp_out,

    //-------------------------------------------------------
    // These pins connect to the QSPI on the GenX chip
    //-------------------------------------------------------
    output reg [3:0] mosi,  // Data to GenX chip
    input      [3:0] miso,  // Data from GenX chip
    output reg       sck,   // QSPI serial clock
    output reg       hcsn,  // host chip select (active low)
    output reg       bcsn   // bank chip select (active low)
    //-------------------------------------------------------

);

// Bring in qspi fields that we will break out from qspi_req_in and qspi_rsp_out
`include "qspi_fields.vh"

// Break out qspi_req_in and qspi_rsp_out into individual fields
assign `QSPI_REQ_FIELDS = qspi_req_in;
assign  qspi_rsp_out    = `QSPI_RSP_FIELDS;

always @(posedge clk) begin
    qspi_rdata <= qspi_wdata;
end 


//=============================================================================
// This function stuffs each bit of an input byte into the bottom bit of each
// nybble of a 32-bit word
//=============================================================================
function[31:0] qspi_reorder_8(reg[7:0] value);
begin
    qspi_reorder_8 = 
    {
        3'b0, value[7],
        3'b0, value[6],
        3'b0, value[5],
        3'b0, value[4],        
        3'b0, value[3],
        3'b0, value[2],
        3'b0, value[1],
        3'b0, value[0]
    };
end 
endfunction 
//=============================================================================


//=============================================================================
// This function reorders a 32-bit word into the order required by QSPI
//=============================================================================
function[31:0] qspi_reorder_32(reg[7:0] value);
begin
    qspi_reorder_32 = 
    {
        value[07:04], value[03:00],
        value[15:12], value[11:08],
        value[23:20], value[19:16],
        value[31:28], value[27:24]
    };
end 
endfunction 
//=============================================================================


//=============================================================================
// Define the clock-cycles required to carry out each type of QSPI transaction
//=============================================================================
localparam QSPI_CMD_CLKS    =  8; // 8 clocks to clock out the QSPI command
localparam QSPI_ADDR_CLKS   =  8; // 8 clocks to clock out the R/W address
localparam QSPI_DATA_CLKS   =  8; // 8 clocks to clock in/out 32 bits of data
localparam QSPI_TAT_CLKS    = 16; // Turn-around time

// Number of clocks to write to a register
localparam QSPI_WREG_CLKS = QSPI_CMD_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_DATA_CLKS;

// Number of clocks to read a register
localparam QSPI_RREG_CLKS = QSPI_CMD_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_TAT_CLKS
                          + QSPI_DATA_CLKS;

// Number of clocks to write to SMEM
localparam QSPI_WMEM_CLKS = QSPI_CMD_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_DATA_CLKS
                          + QSPI_DATA_CLKS;

// Number of clocks to write to SMEM
localparam QSPI_RMEM_CLKS = QSPI_CMD_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_TAT_CLKS
                          + QSPI_DATA_CLKS
                          + QSPI_DATA_CLKS;

// This is how large the buffer needs to be (in bits) in order to hold
// our longest possible message
localparam TX_BUFF_SIZE = QSPI_RMEM_CLKS;
//=============================================================================

// Number of nanoseconds per clk
localparam NS_PER_CLK = 1000000000 / FREQ_HZ;

// How many clock cycles are there per SCK cycle?
localparam CLK_PER_SCK = FREQ_HZ / QSPI_FREQ;

// Round CLK_PER_SCK up to the nearest even number.  This ensures that the frequency of SCK
// will never be higher than the frequency requested via the SPI_FREQ parameter
localparam EVEN_CLK_PER_SCK = (CLK_PER_SCK & 1) ? CLK_PER_SCK + 1 : CLK_PER_SCK;

// Ensure that SPI_SCK_DELAY is 0 or positive
localparam QSPI_SCK_DELAY = (EVEN_CLK_PER_SCK > 2) ? (EVEN_CLK_PER_SCK / 2) - 1 : 0;

// The chip-selects are active low
localparam CHIP_SELECT = 0;

// These are the possible states of "qsm_state"
localparam QSM_IDLE          = 0;
localparam QSM_FALLING_SCK   = 1;
localparam QSM_RISING_SCK    = 2;
localparam QSM_WAIT_COMPLETE = 3;

//=============================================================================
// This block clocks data out via the QSPI bus "sck" and "mosi" pins
//
// "mosi" can only change values when "sck" is low.
//
// Prior to strobing tx_start high:
//    Ensure that tx_idle = 1
//    tx_dataword    = The bits to be transmitted
//    tx_cycle_count = The number of bits in the transaction
//=============================================================================
reg                    tx_start;
reg [TX_BUFF_SIZE-1:0] tx_dataword; 
reg [7:0]              tx_cycle_count;
//-----------------------------------------------------------------------------
reg [             3:0] qsm_state;
reg [            15:0] qsm_delay;
reg [             6:0] qsm_cycle_counter;
reg [TX_BUFF_SIZE-1:0] qsm_dataword;
//-----------------------------------------------------------------------------
wire tx_idle = (qsm_state == QSM_IDLE) & (tx_start == 0);
//-----------------------------------------------------------------------------

always @(posedge clk) begin

    // This is a countdown timer
    if (qsm_delay) qsm_delay <= qsm_delay - 1;

    if (resetn == 0) begin
        qsm_state <= QSM_IDLE;
        sck       <= 0;
    end

    else case(qsm_state)

        // Here we wait for a new command to arrive
        QSM_IDLE:
            if (tx_start) begin
                sck               <= 0;
                qsm_delay         <= 0;
                qsm_cycle_counter <= 0;
                qsm_dataword      <= tx_dataword;
                qsm_state         <= QSM_FALLING_SCK;
            end

        // Drive out the next outgoing bit on sdo, and drive SCK low
        QSM_FALLING_SCK:
            if (qsm_delay == 0) begin
                sck          <= 0;
                mosi         <= qsm_dataword[TX_BUFF_SIZE-1 -: 4];
                qsm_dataword <= qsm_dataword << 4;
                if (qsm_cycle_counter < tx_cycle_count) begin
                    qsm_delay <= QSPI_SCK_DELAY;
                    qsm_state <= QSM_RISING_SCK;
                end else begin
                    qsm_delay <= 20/NS_PER_CLK;
                    qsm_state <= QSM_WAIT_COMPLETE;
                end

            end

        // Drive SCK high
        QSM_RISING_SCK:
            if (qsm_delay == 0) begin
                sck               <= 1;
                qsm_delay         <= QSPI_SCK_DELAY;
                qsm_cycle_counter <= qsm_cycle_counter + 1;
                qsm_state         <= QSM_FALLING_SCK;
            end

        // Wait for the final timer to expire before returning to idle
        QSM_WAIT_COMPLETE:
            if (qsm_delay == 0) qsm_state <= QSM_IDLE;

    endcase

end
//=============================================================================




//=============================================================================
// Broken out QSPI interface fields for debugging
//=============================================================================
`ifdef ADD_DEBUG_PORTS
    assign dbg_qspi_cmd   = qspi_cmd  ;  
    assign dbg_qspi_addr  = qspi_addr ; 
    assign dbg_qspi_wdata = qspi_wdata;
    assign dbg_qspi_start = qspi_start;
    assign dbg_qspi_rdata = qspi_rdata; 
    assign dbg_qspi_idle  = qspi_idle ;
`endif
//=============================================================================

endmodule
