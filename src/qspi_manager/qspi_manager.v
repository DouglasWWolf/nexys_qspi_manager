
//=======================================================================================
// This module manages QSPI transactions.
//
// There are two primary state machines.   The first of these drives low-level QSPI 
// transactions, everything from the time a chip-select is asserted to the time the
// chip select is released.
//
// The other state machine is a "command handler".   A client module can send a commands
// such as "Read 64-bit word from SMEM on bank 2" and this state machine will initiate
// the neccessary sequence of QSPI transactions to carry out the requested command.
//
//=======================================================================================

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
    output reg [3:0] mosi,      // Data to GenX chip
    input      [3:0] miso,      // Data from GenX chip
    output reg       sck,       // QSPI serial clock
    wire             host_csn,  // host chip select (active low)
    wire             bank_csn   // bank chip select (active low)
    //-------------------------------------------------------

);

integer i;

// A GenX "host register" that allows us to select 1 or more banks
localparam QSPI_BANK_EN_REG = 32'h28;

// SMEM starts at this address in all banks
localparam FIRST_SMEM_ADDR  = 32'h10_0000;

// Bring in qspi fields that we will break out from qspi_req_in and qspi_rsp_out
`include "qspi_fields.vh"

// Break out qspi_req_in and qspi_rsp_out into individual fields
assign `QSPI_REQ_FIELDS = qspi_req_in;
assign  qspi_rsp_out    = `QSPI_RSP_FIELDS;

// Bad parameters can result in one of these errors
reg[2:0]   qspi_error;
localparam ERROR_NONE      = 0;
localparam ERROR_BANKSEL   = 1;
localparam ERROR_ADDRESS   = 2;
localparam ERROR_UNALIGNED = 3;
localparam ERROR_BAD_CMD   = 4;

// This is the most recent 64 bits clocked in from the QSPI's miso pins
reg[63:0] read_result;

//=============================================================================
// chip_select[] controls the two chip select lines "host_csn" and "bank_csn".
//=============================================================================
reg[1:0] chip_select;
localparam CS_HOST = 2'b10;
localparam CS_BANK = 2'b01;
localparam CS_NONE = 2'b11;
assign host_csn = chip_select[0];
assign bank_csn = chip_select[1];
localparam CS_DELAY_NS = 60;
//=============================================================================


//=============================================================================
// This function stuffs each bit of an input byte into the bottom bit of each
// nybble of a 32-bit word
//=============================================================================
function[31:0] make_opcode(reg[7:0] value);
begin
    make_opcode = 
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
// This function reverses the order of the bytes in a 32-bit input value
//=============================================================================
function[31:0] swap_endian(reg[31:0] value);
begin
    swap_endian = {value[07:00], value[15:08], value[23:16], value[31:24]};
end 
endfunction 
//=============================================================================

//=============================================================================
// This block counts the number of 1 bits in "qspi_bankmap"
//=============================================================================
reg[3:0] bank_count;
always @* begin
    bank_count = 0;
    for (i=0; i<10; i=i+1) begin
        if (qspi_bankmap[i]) bank_count = bank_count + 1;
    end
end
//=============================================================================


//=============================================================================
// Define the clock-cycles required to carry out each type of QSPI transaction
//=============================================================================
localparam QSPI_OPCODE_CLKS =  8; // 8 clocks to clock out the QSPI command
localparam QSPI_ADDR_CLKS   =  8; // 8 clocks to clock out the R/W address
localparam QSPI_DATA_CLKS   =  8; // 8 clocks to clock in/out 32 bits of data
localparam QSPI_TAT_CLKS    = 16; // Turn-around time

// Number of clocks to write to a register
localparam QSPI_WREG_CLKS = QSPI_OPCODE_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_DATA_CLKS;

// Number of clocks to read a register
localparam QSPI_RREG_CLKS = QSPI_OPCODE_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_TAT_CLKS
                          + QSPI_DATA_CLKS;

// Number of clocks to write to 64-bits to SMEM
localparam QSPI_WMEM_CLKS = QSPI_OPCODE_CLKS
                          + QSPI_ADDR_CLKS
                          + 2 * QSPI_DATA_CLKS;

// Number of clocks to write read 64-bits from SMEM
localparam QSPI_RMEM_CLKS = QSPI_OPCODE_CLKS
                          + QSPI_ADDR_CLKS
                          + QSPI_TAT_CLKS
                          + 2 * QSPI_DATA_CLKS;
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


//=============================================================================
// This block clocks data out via the QSPI bus "sck" and "mosi" pins
//
// Prior to strobing tx_start high:
//    Ensure that tx_idle = 1
//    tx_cs          = Either CS_HOST or CS_BANK
//    tx_opcode      = QSPI opcode, in the low bit of every nybble
//    tx_address     = register or SMEM address,  little-endian
//    tx_wdata[N]    = Nth word of data to write, little-endian
//    tx_cycle_count = The number of bits in the transaction
//  
// "mosi" is clocked out on the rising edge of sck.
// "mosi" changes state on the falling edge of sck
// 
//=============================================================================
reg        tx_start;
reg [ 1:0] tx_cs;
reg [31:0] tx_opcode;
reg [31:0] tx_address;
reg [31:0] tx_wdata[0:7];
reg [ 7:0] tx_cycle_count;
//-----------------------------------------------------------------------------
localparam QSM_DATAWORD_LEN = 320; /* tx_opcode + tx_address + tx_wdata[0:7] */
reg [                 3:0] qsm_state;
reg [                 5:0] qsm_delay;
reg [                 6:0] qsm_cycle_counter;
reg [QSM_DATAWORD_LEN-1:0] qsm_dataword;
//-----------------------------------------------------------------------------
// These are the states for qsm_state
//-----------------------------------------------------------------------------
localparam QSM_IDLE          = 0;
localparam QSM_ASSERT_CS     = 1;
localparam QSM_FALLING_SCK   = 2;
localparam QSM_RISING_SCK    = 3;
localparam QSM_RELEASE_CS    = 4;
localparam QSM_WAIT_COMPLETE = 5;
//-----------------------------------------------------------------------------
// This is high when this state machine is idle
//-----------------------------------------------------------------------------
wire tx_idle = (qsm_state == QSM_IDLE) & (tx_start == 0);
wire sck_rising_edge = (qsm_state == QSM_RISING_SCK) & (qsm_delay == 0);
//-----------------------------------------------------------------------------

always @(posedge clk) begin

    // This is a countdown timer
    if (qsm_delay) qsm_delay <= qsm_delay - 1;

    if (resetn == 0) begin
        qsm_state   <= QSM_IDLE;
        sck         <= 0;
        chip_select <= CS_NONE;
    end

    else case(qsm_state)

        // Here we wait for a new command to arrive
        QSM_IDLE:
            if (tx_start) begin
                chip_select       <= tx_cs;
                sck               <= 0;
                qsm_delay         <= CS_DELAY_NS / NS_PER_CLK;
                qsm_cycle_counter <= 0;
                qsm_dataword      <= {
                                        tx_opcode, tx_address,
                                        tx_wdata[0], tx_wdata[1], tx_wdata[2], tx_wdata[3],
                                        tx_wdata[4], tx_wdata[5], tx_wdata[6], tx_wdata[7]
                                     };
                qsm_state         <= QSM_ASSERT_CS;
            end

        // Need a delay after asserting chip-select
        QSM_ASSERT_CS:
            if (qsm_delay == 0) qsm_state <= QSM_FALLING_SCK;

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
                    qsm_state <= QSM_RELEASE_CS;
                end

            end

        // Drive SCK high.  Data is clocked in by the peer QSPI on highgoing edges of clk
        QSM_RISING_SCK:
            if (qsm_delay == 0) begin
                sck               <= 1;
                qsm_delay         <= QSPI_SCK_DELAY;
                qsm_cycle_counter <= qsm_cycle_counter + 1;
                qsm_state         <= QSM_FALLING_SCK;
            end

        // Here we release the chip-select
        QSM_RELEASE_CS:
            begin
                chip_select <= CS_NONE;
                qsm_delay   <= CS_DELAY_NS/NS_PER_CLK;
                qsm_state   <= QSM_WAIT_COMPLETE;
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
        if      (qspi_cmd == QSPI_CMD_RD_HREG && qspi_addr == 0)
            flip_flop <= 4'b0001;
        else if (qspi_cmd == QSPI_CMD_RD_HREG && qspi_addr == 4)
            flip_flop <= 4'b0010;
        else if (qspi_cmd == QSPI_CMD_RD_BREG && qspi_addr == 0)
            flip_flop <= 4'b0100;
        else if (qspi_cmd == QSPI_CMD_RD_BREG && qspi_addr == 4)
            flip_flop <= 4'b1000;
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
reg [6:0] fsm_state, fsm_next_state;
//-----------------------------------------------------------------------------
// These are the states for fsm_state
//-----------------------------------------------------------------------------
localparam FSM_IDLE        =  0;
localparam FSM_BANK_SELECT =  1;
localparam FSM_WR_HREG     =  5;
localparam FSM_RD_HREG     = 10;
localparam FSM_WR_BREG     = 15;
localparam FSM_RD_BREG     = 20;
localparam FSM_WR_SMEM     = 25;
localparam FSM_RD_SMEM     = 30;
localparam FSM_WR_BULK     = 35;
localparam FSM_RD_BULK     = 40;
localparam FSM_CMD_END     = 45;
//-----------------------------------------------------------------------------

// Clear all of the tx_wdata
`define CLEAR_TX_WDATA  tx_wdata[0] <= 0; tx_wdata[1] <= 0; tx_wdata[2] <= 0; tx_wdata[3] <= 0; \
                        tx_wdata[4] <= 0; tx_wdata[5] <= 0; tx_wdata[6] <= 0; tx_wdata[7] <= 0

always @(posedge clk) begin

    // This strobes high for a single cycle at a time
    tx_start <= 0;

    if (resetn == 0) begin
        fsm_state <= 0;
    end

    else case(fsm_state)

        // Here we wait to be told to start
        FSM_IDLE:
            if (qspi_start) begin

                // By default, no error has occured
                qspi_error <= 0;

                // Perform the appropriate command
                case(qspi_cmd)

                    // Write to host register
                    QSPI_CMD_WR_HREG: 
                        if (qspi_addr >= FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 3)
                            qspi_error <= ERROR_UNALIGNED;
                        else
                            fsm_state <= FSM_WR_HREG;
                    
                    // Read host register
                    QSPI_CMD_RD_HREG: 
                        if (qspi_addr >= FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 3)
                            qspi_error <= ERROR_UNALIGNED;
                        else
                            fsm_state <= FSM_RD_HREG;
                    
                    // Write to bank register
                    QSPI_CMD_WR_BREG:
                        if (bank_count == 0)
                            qspi_error <= ERROR_BANKSEL;
                        else if (qspi_addr >= FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 3)
                            qspi_error <= ERROR_UNALIGNED;
                        else begin
                            fsm_state      <= FSM_BANK_SELECT;
                            fsm_next_state <= FSM_WR_BREG;
                        end

                    // Read bank register
                    QSPI_CMD_RD_BREG:
                        if (bank_count != 1)
                            qspi_error <= ERROR_BANKSEL;
                        else if (qspi_addr >= FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 3)
                            qspi_error <= ERROR_UNALIGNED;
                        else begin
                            fsm_state      <= FSM_BANK_SELECT;
                            fsm_next_state <= FSM_RD_BREG;
                        end

                    // Write a 64-bit value to SMEM
                    QSPI_CMD_WR_SMEM:
                        if (bank_count == 0)
                            qspi_error <= ERROR_BANKSEL;
                        else if (qspi_addr < FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 7)
                            qspi_error <= ERROR_UNALIGNED;
                        else begin
                            fsm_state      <= FSM_BANK_SELECT;
                            fsm_next_state <= FSM_WR_SMEM;                    
                        end

                    // Write a 64-bit value to SMEM
                    QSPI_CMD_RD_SMEM:
                        if (bank_count != 1)
                            qspi_error <= ERROR_BANKSEL;
                        else if (qspi_addr < FIRST_SMEM_ADDR)
                            qspi_error <= ERROR_ADDRESS;
                        else if (qspi_addr & 7)
                            qspi_error <= ERROR_UNALIGNED;
                        else begin
                            fsm_state      <= FSM_BANK_SELECT;
                            fsm_next_state <= FSM_RD_SMEM;                    
                        end

                    // Anything else is an unknown command
                    default:
                        qspi_error <= ERROR_BAD_CMD;

                endcase
            end 

        // Write a value to the QSPI_BANK_EN_REG "bank select" register
        FSM_BANK_SELECT:
            begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_HOST;
                tx_opcode      <= make_opcode(OPCODE_WRITE_SINGLE);
                tx_address     <= swap_endian(QSPI_BANK_EN_REG);
                tx_wdata[0]    <= swap_endian(qspi_bankmap);
                tx_cycle_count <= QSPI_WREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= fsm_next_state;
            end

        // Write to a 32-bit host register
        FSM_WR_HREG:
            begin 
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_HOST;
                tx_opcode      <= make_opcode(OPCODE_WRITE_SINGLE);
                tx_address     <= swap_endian(qspi_addr);
                tx_wdata[0]    <= swap_endian(qspi_wdata[31:0]);
                tx_cycle_count <= QSPI_WREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Read from a 32-bit host register
        FSM_RD_HREG:
            begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_HOST;
                tx_opcode      <= make_opcode(OPCODE_READ_SINGLE);
                tx_address     <= swap_endian(qspi_addr);
                tx_cycle_count <= QSPI_RREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Write to a 32-bit bank register in one or more banks
        FSM_WR_BREG:
            if (tx_idle) begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_BANK;
                tx_opcode      <= make_opcode(OPCODE_WRITE_SINGLE);
                tx_address     <= swap_endian(qspi_addr);
                tx_wdata[0]    <= swap_endian(qspi_wdata[31:0]);
                tx_cycle_count <= QSPI_WREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Read from a 32-bit bank register
        FSM_RD_BREG:
            if (tx_idle) begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_BANK;
                tx_opcode      <= make_opcode(OPCODE_READ_SINGLE);
                tx_address     <= swap_endian(qspi_addr);
                tx_cycle_count <= QSPI_RREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Write a 64-bit value to SMEM
        FSM_WR_SMEM:
            if (tx_idle) begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_BANK;
                tx_opcode      <= make_opcode(OPCODE_WRITE_BURST);
                tx_address     <= swap_endian(qspi_addr);
                tx_wdata[0]    <= swap_endian(qspi_wdata[1*32 +: 32]);
                tx_wdata[1]    <= swap_endian(qspi_wdata[0*32 +: 32]);
                tx_cycle_count <= QSPI_WMEM_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Read a single 32-bit word from SMEM and throw away the
        // result.   This is required by the GenX hardware
        FSM_RD_SMEM:
            if (tx_idle) begin 
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_BANK;
                tx_opcode      <= make_opcode(OPCODE_READ_SINGLE);
                tx_address     <= swap_endian(qspi_addr);
                tx_cycle_count <= QSPI_RREG_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_RD_SMEM+1;
            end


        // Read a 64-bit value from SMEM
        FSM_RD_SMEM+1:
            if (tx_idle) begin
                `CLEAR_TX_WDATA;
                tx_cs          <= CS_BANK;
                tx_opcode      <= make_opcode(OPCODE_READ_BURST);
                tx_address     <= swap_endian(qspi_addr);
                tx_cycle_count <= QSPI_RMEM_CLKS;
                tx_start       <= 1;
                fsm_state      <= FSM_CMD_END;
            end

        // Wait for the most recent QSPI transaction to finish
        FSM_CMD_END:
            if (tx_idle) begin
                qspi_rdata <= read_result[63:0];
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
    qspi_idle = (fsm_state == FSM_IDLE) & (qspi_start == 0);
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
