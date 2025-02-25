//=============================================================================
// Module: gxsim_qspi.v
//
// Serves as the QSPI slave
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
    output reg [        9:0] sck_counts,   // Count of the rising edges of SCK
    output reg [        7:0] opcode,       // Opcode that arrived on MOSI
    output reg [       31:0] address,      // Address that arrived on MOSI
    output reg [        1:0] chip_select,  // Which chip-selects are active?
    output     [SMEM_BW-1:0] wdata,        // Data to be written to registers or SMEM
    input      [SMEM_BW-1:0] rdata,        // Data read from registers or SMEM
    output reg               notify_read,  // Rising edge = A reg/SMEM read may be req'd
    output reg               notify_write  // Rising edge = A reg/SMEM write may be req'd

);
genvar i;
 
// The number of 32-bit words that will fit into wdata or rdata
localparam SMEM_DW = SMEM_BW / 32;

// We're going to turn the wdata port into an array of 32 bit values
reg[31:0] wdata_array[0:SMEM_DW-1];

// Now map wdata_array into the wdata
for (i=0; i<SMEM_DW; i=i+1) begin
    assign wdata[(SMEM_DW-1-i)*32 +: 32] = wdata_array[i];
end

// Wire the two chip-selects together, cs will go low if either chip-select goes low.
wire cs = host_csn & bank_csn;

// Data arriving on MOSI is clocked into this buffer
reg[31:0] buffer;

// When read-data is available from genx_qspi_handler, we'll store it here
reg[SMEM_BW-1:0] reg_rdata;

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
reg [ 9:0] clock_number = 1;
wire[31:0] current_input_word = {buffer[27:0], mosi};
//-----------------------------------------------------------------------------
always @(posedge sck, posedge cs) begin

    // The positive edge of chip-select serves as a "reset" of sorts
    if (cs == 1) begin
        clock_number <= 1;
        buffer       <= 0;
        notify_write <= 1;
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
// MISO is the top 4 bits of reg_rdata
assign miso = (sck_counts < 32) ? 0 : reg_rdata[SMEM_BW-1 -: 4];
//-----------------------------------------------------------------------------
always @(negedge sck) begin

    // Preload the first nybble into MISO so that it's ready to go
    // when we start clocking bits out on rising edges of SCK
    if (sck_counts == 30) begin
        reg_rdata <= rdata;
    end
    
    // If we're clocking bits out, shift the read-data left by 4 bits
    // on every falling edge when we are clocking out data
    else if (sck_counts > 32) begin
        reg_rdata <= reg_rdata << 4;
    end
end
//=============================================================================


//=============================================================================
// This block manages the wdata_array.  We have a complete 32-bit word to store
// into wdata_array[] on clock cycles 24, 32, 40, 48, etc.
//=============================================================================
for (i=0; i<SMEM_DW; i=i+1) begin
    always @(posedge sck) begin
        if (clock_number == 1)
            wdata_array[i] <= 0;
        else if (clock_number == 24 + 8*i)
            wdata_array[i] <= current_input_word;
    end
end
//=============================================================================


endmodule
