


module genx_qspi_sim # (parameter DATA_RCVD_SIZE = 256)
( 
    
    
    input       sck,
    input [3:0] mosi,
    output[3:0] miso,
    input       host_csn,
    input       bank_csn,


    output reg [ 9:0] sck_counts,   // Count of the rising edges of SCK
    output reg [ 7:0] opcode,       // Opcode that arrived on MOSI
    output reg [31:0] address,      // Address that arrived on MOSI
    output reg [ 1:0] chip_select,  // Which chip-selects are active?
    output reg        notify_read,  // Rising edge = A reg/SMEM read may be req'd
    output reg        notify_write  // Rising edge = A reg/SMEM write may be req'd
);

assign miso = 0;

// Wire the two chip-selects together, cs will go low if either chip-select goes low.
wire cs = host_csn & bank_csn;


localparam BUFF_SIZE = 512;
reg[BUFF_SIZE-1:0] buffer;


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
reg[9:0] clock_number = 1;
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
        buffer <= {buffer[BUFF_SIZE-5:0], mosi};

        // On specific clock numbers, need to record various data
        case (clock_number) 

            // De-assert the notification signals and tell the handler
            // the state of the chip-select inputs
            1:  begin
                    notify_read  <= 0;
                    notify_write <= 0;
                    chip_select  <= {bank_csn, host_csn};
                end

            8:  begin
                    opcode <= decode_opcode({buffer[27:0], mosi});
                end

            16: begin
                    address     <= swap_endian({buffer[27:0], mosi});
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


endmodule
