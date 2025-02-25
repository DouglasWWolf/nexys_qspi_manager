//=============================================================================
// Module: gxsim_qspi.v
//
// Serves as the QSPI slave
//
// The "notify-write" signal goes high as we clock out the last bit of a 
// each 32-bit word to be written to a SMEM, SMEM buffer, a register, etc.
//
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================

module gxsim_qspi #
(
    parameter SMEM_BW = 512  // Number of bits in an SMEM "burst" read/write
)
( 
    // These are the pins of the QSPI interface
    input       sck,
    input [3:0] mosi,
    output[3:0] miso,
    input       host_csn, 
    input       bank_csn,

    // This is the interface to the "gxsim_qspi_handler" module
    output                   rw,           // 1 = This is a write, 0 = This is a read
    output reg [        9:0] sck_counts,   // Count of the rising edges of SCK
    output reg [       31:0] address,      // Address that arrived on MOSI
    output reg [        1:0] chip_select,  // Which chip-selects are active?
    output reg [       31:0] wdata,        // Data to be written to registers or SMEM
    input      [SMEM_BW-1:0] rdata,        // Data read from registers or SMEM
    output reg               notify_read,  // Rising edge = A reg/SMEM read may be req'd
    output reg               notify_write  // Rising edge = A reg/SMEM write may be req'd

);

// Haul in system-wide localparam definitions
`include "../includes/sys_params.vh"

genvar i;


// The possible values of the "rw" port
localparam RW_READ  = 0;
localparam RW_WRITE = 1;

// The number of 32-bit words that will fit into wdata or rdata
localparam SMEM_DW = SMEM_BW / 32;

// Wire the two chip-selects together, cs will go low if either chip-select goes low.
wire cs = host_csn & bank_csn;

// This is the QSPI opcode that tells us whether it's a read or a write
reg[7:0] opcode;

// This is high if the opcode is a write operation
assign rw = (opcode == GENX_QSPI_OPCODE_WRITE_SINGLE)
          | (opcode == GENX_QSPI_OPCODE_WRITE_BURST );

// Data arriving on MOSI is clocked into this buffer
reg[31:0] buffer;

// This is data actively being clocked out on MISO
reg[SMEM_BW-1:0] clocking_out;

//=============================================================================
// This decodes an 8-bit opcode (that was smeared across 32 bit) back into
// an 8 bit value
//=============================================================================
function[7:0] decode_opcode(reg[31:0] f);
begin
    decode_opcode = {f[28], f[24], f[20], f[16], f[12], f[8], f[4], f[0]};
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
// This state machine clocks data in and out on the rising edge of sck
//=============================================================================
reg [15:0] clock_number = 1;
wire[31:0] current_input_word = {buffer[27:0], mosi};
//-----------------------------------------------------------------------------
always @(posedge sck, posedge cs) begin

    // The positive edge of chip-select serves as a "reset" of sorts
    if (cs == 1) begin
        clock_number <= 1;
        buffer       <= 0;
    end

    // Otherwise, 4-bits just arrived on MOSI
    else begin
   
        // Shift MOSI into the bottom 4 bits of the buffer
        buffer <= current_input_word; 

        // On specific clock numbers, need to record various data
        case (clock_number) 

            // De-assert the notification signals and tell the handler
            // the state of the chip-select inputs
            1:  begin
                    notify_read  <= 0;
                    notify_write <= 0;
                    chip_select  <= {bank_csn, host_csn};
                end

            // At the 8th SCK cycle, we have an opcode
            8:  begin
                    opcode <= decode_opcode(current_input_word);
                end

            // At the end of the 16th SCK cycle, we have an address to read/write from/to
            16: begin
                    address     <= swap_endian(current_input_word);
                    notify_read <= 1;
                end
        endcase 

        // After clock 16, every 8th clock will cause us to strobe
        // "notify_write" high.  4 clocks after it goes high, it will go low
        // again.   This gives us a rising edge of notify_write on sck 
        // number 24, 32, 40, 48, 56, etc.  We leave it high for 4 sck cycles
        // in order to allow time for the the qspi_handler module to 
        // synchronize the incoming "notify_write" signal and detect rising
        // edges.
        //
        // Refresher:
        //   clock_number  1 thru  8  = The opcode is received
        //   clock number  9 thru 16  = The address is received
        //   clock_number 17 thru 24  = Data word #1 is received
        //   clock_number 25 thru 32  = Data word #2 is received
        //   clock_number 26 thru 40  = Data word #3 is received (etc)
        //
        if (rw == RW_WRITE && clock_number >= 24) begin
            if (clock_number[2:0] == 3'b000) begin
                wdata <= current_input_word;
                if (clock_number >= 32) begin
                    address <= address + 4; // inc the address to the next 32-bit word
                end
                notify_write <= 1;
            end

            else if (clock_number[2:0] == 3'b100)
                notify_write <= 0;
        end


        // Tell the outside world how many rising edge of SCK we've seen
        sck_counts <= clock_number;

        // And set up for the next clock cycle
        clock_number <= clock_number + 1;
    end

end
//=============================================================================



//=============================================================================
// This state machine changes MISO on the falling edge of SCK, starting with
// SCK number 32.  The gaurantees that the data we want to output on MISO
// will be available on the rising edge of SCK number 33
//=============================================================================
// MISO is the top 4 bits of clocking_out
assign miso = (sck_counts < 32) ? 0 : clocking_out[SMEM_BW-1 -: 4];
//-----------------------------------------------------------------------------
always @(negedge sck) begin

    // Preload the first nybble into MISO so that it's ready to go
    // when we start clocking bits out on rising edges of SCK
    if (sck_counts == 30) begin
        clocking_out <= rdata;
    end
    
    // If we're clocking bits out, shift the read-data left by 4 bits
    // on every falling edge when we are clocking out data
    else if (sck_counts > 32) begin
        clocking_out <= clocking_out << 4;
    end
end
//=============================================================================

endmodule
