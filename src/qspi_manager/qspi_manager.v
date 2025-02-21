


// We want the QSPI interface signals broken out for debug
`define ADD_DEBUG_PORTS

// We want to use simulated input data on the miso pins
`define SIM_MISO

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
        output [    `QSPI_CMD_LEN-1:0] dbg_qspi_cmd,  
        output [`QSPI_BANKMAP_LEN-1:0] dbg_qspi_bankmap,  
        output [   `QSPI_ADDR_LEN-1:0] dbg_qspi_addr, 
        output [  `QSPI_WDATA_LEN-1:0] dbg_qspi_wdata,
        output [  `QSPI_START_LEN-1:0] dbg_qspi_start,
        output [  `QSPI_RDATA_LEN-1:0] dbg_qspi_rdata, 
        output [   `QSPI_IDLE_LEN-1:0] dbg_qspi_idle,
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

// This is the most recent 64 bits clocked in from the QSPI's miso pins
reg[63:0] read_result;

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
function[31:0] qspi_endian(reg[31:0] value);
begin
    qspi_endian = 
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

// Number of clocks to write read SMEM
localparam QSPI_RMEM_CLKS = QSPI_CMD_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_TAT_CLKS
                          + QSPI_DATA_CLKS
                          + QSPI_DATA_CLKS;

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


//=============================================================================
// This block clocks data out via the QSPI bus "sck" and "mosi" pins
//
// "mosi" can only change values when "sck" is low.
//
// Prior to strobing tx_start high:
//    Ensure that tx_idle = 1
//    tx_opcode      = QSPI opcode, in the low bit of every nybble
//    tx_address     = register or SMEM address,  QSPI-endian
//    tx_wdata0      = 1st word of data to write, QSPI-endian
//    tx_wdata1      = 2nd word of data to write, QSPI-endian
//    tx_cycle_count = The number of bits in the transaction
//=============================================================================
reg        tx_start;
reg [31:0] tx_opcode;
reg [31:0] tx_address;
reg [31:0] tx_wdata0;
reg [31:0] tx_wdata1;
reg [ 7:0] tx_cycle_count;
//-----------------------------------------------------------------------------
localparam QSM_DATAWORD_LEN = 128;
reg [                 3:0] qsm_state;
reg [                 5:0] qsm_delay;
reg [                 6:0] qsm_cycle_counter;
reg [QSM_DATAWORD_LEN-1:0] qsm_dataword;
//-----------------------------------------------------------------------------
// These are the states for qsm_state
//-----------------------------------------------------------------------------
localparam QSM_IDLE          = 0;
localparam QSM_FALLING_SCK   = 1;
localparam QSM_RISING_SCK    = 2;
localparam QSM_WAIT_COMPLETE = 3;
//-----------------------------------------------------------------------------
// This is high when this state machine is idle
//-----------------------------------------------------------------------------
wire tx_idle = (qsm_state == QSM_IDLE) & (tx_start == 0);
wire sck_rising_edge = (qsm_state == QSM_RISING_SCK) & (qsm_delay == 0);
//-----------------------------------------------------------------------------
// We program this host register to select banks for writes to SMEM or writes
// to bank registers
//-----------------------------------------------------------------------------
localparam QSPI_BANK_EN_REG = 32'h28;
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
                qsm_dataword      <= {tx_opcode, tx_address, tx_wdata0, tx_wdata1};
                qsm_state         <= QSM_FALLING_SCK;
            end

        // Drive out the next outgoing nybble on mosi, and drive SCK low
        QSM_FALLING_SCK:
            if (qsm_delay == 0) begin
                 
                sck          <= 0;
                mosi         <= qsm_dataword[QSM_DATAWORD_LEN-1 -: 4];
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
// These are the opcodes that the GenX QSPI receiver understands
//=============================================================================
localparam[7:0] OPCODE_READ_SINGLE  = 8'hE8;
localparam[7:0] OPCODE_WRITE_SINGLE = 8'hE9;
localparam[7:0] OPCODE_READ_BURST   = 8'hEA;
localparam[7:0] OPCODE_WRITE_BURST  = 8'hEB;
//=============================================================================



//=============================================================================
// This block clocks data from the QSPI's miso pins into "read_result"
//=============================================================================
reg[3:0] flip_flop;

always @(posedge clk) begin
    
    if (resetn == 0) begin
        read_result <= 0;
    end


    else if (tx_start) begin
        if      (qspi_cmd == QSPI_CMD_RHR && qspi_addr == 0)
            flip_flop <= 4'b0101;
        else if (qspi_cmd == QSPI_CMD_RHR && qspi_addr == 4)
            flip_flop <= 4'b1100;
        else 
            flip_flop <= 0;
    end


    else if (sck_rising_edge) begin
        `ifdef SIM_MISO
            read_result <= (read_result << 4) | flip_flop;        
            if (flip_flop) flip_flop   <= ~flip_flop;
        `else
            read_result <= (read_result << 4) | miso;
        `endif
    end

end
//=============================================================================


//=============================================================================
// This state machine handles incoming transaction requests
//=============================================================================
reg [6:0] fsm_state;
//-----------------------------------------------------------------------------
// These are the states for fsm_state
//-----------------------------------------------------------------------------
localparam FSM_IDLE      =  0;
localparam FSM_CMD_WHR   = 10;
localparam FSM_CMD_WBR   = 20;
localparam FSM_CMD_RHR   = 30;
localparam FSM_CMD_RBR   = 40;
localparam FSM_CMD_RMEM  = 50;
localparam FSM_CMD_WMEM  = 60;
localparam FSM_CMD_END   = 70;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    // This strobes high for a single cycle at a time
    tx_start <= 0;

    if (resetn == 0) begin
        fsm_state <= 0;
        hcsn      <= ~CHIP_SELECT;
        bcsn      <= ~CHIP_SELECT;
    end

    else case(fsm_state)

        // Here we wait to be told to start
        FSM_IDLE:
            if (qspi_start) begin
                case(qspi_cmd)
                    QSPI_CMD_WHR:   fsm_state <= FSM_CMD_WHR;
                    QSPI_CMD_WBR:   fsm_state <= FSM_CMD_WBR;
                    QSPI_CMD_RHR:   fsm_state <= FSM_CMD_RHR;
                    QSPI_CMD_RBR:   fsm_state <= FSM_CMD_RBR;
                    QSPI_CMD_RMEM:  fsm_state <= FSM_CMD_RMEM;
                    QSPI_CMD_WMEM:  fsm_state <= FSM_CMD_WMEM;
                endcase
            end

        // Write to host register
        FSM_CMD_WHR:
            begin
                hcsn           <= CHIP_SELECT;
                tx_opcode      <= qspi_reorder_8(OPCODE_WRITE_SINGLE);
                tx_address     <= qspi_endian(qspi_addr);
                tx_wdata0      <= qspi_endian(qspi_wdata[31:0]);
                tx_wdata1      <= 0;
                tx_cycle_count <= QSPI_WREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        FSM_CMD_RHR:
            begin
                hcsn           <= CHIP_SELECT;
                tx_opcode      <= qspi_reorder_8(OPCODE_READ_SINGLE);
                tx_address     <= qspi_endian(qspi_addr);
                tx_wdata0      <= 0;
                tx_wdata1      <= 0;
                tx_cycle_count <= QSPI_RREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end


        FSM_CMD_END:
            if (tx_idle) begin
                hcsn       <= ~CHIP_SELECT;
                bcsn       <= ~CHIP_SELECT;
                qspi_rdata <= read_result;
                fsm_state  <= FSM_IDLE;
            end

    endcase
end
//=============================================================================


//=============================================================================
// This blocks ensures that qspi_idle is active when our main state machine
// is idle and waiting for a command
//=============================================================================
always @* begin
    qspi_idle = (FSM_STATE == FSM_IDLE) & (qspi_start == 0);
end
//=============================================================================


//=============================================================================
// Broken out QSPI interface fields for debugging
//=============================================================================
`ifdef ADD_DEBUG_PORTS
    assign dbg_qspi_cmd     = qspi_cmd    ;  
    assign dbg_qspi_bankmap = qspi_bankmap; 
    assign dbg_qspi_addr    = qspi_addr   ; 
    assign dbg_qspi_wdata   = qspi_wdata  ;
    assign dbg_qspi_start   = qspi_start  ;
    assign dbg_qspi_rdata   = qspi_rdata  ; 
    assign dbg_qspi_idle    = qspi_idle   ;
`endif
//=============================================================================

endmodule
