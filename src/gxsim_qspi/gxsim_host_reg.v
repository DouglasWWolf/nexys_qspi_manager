//=============================================================================
// Module: gxsim_host_reg
//
// Simulates the GenX host-registers
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================
`include "../includes/sys_defines.vh"

module gxsim_host_reg
(
    input   clk, resetn,

    // The byte address of the register being read or written
    input [31:0] address,
        
    // The data to write to the address
    input [31:0] wdata,

    // When this strobes high, "wdata" is saved 
    input write_strobe,

    // The data to read from the address
    output reg[31:0] rdata,

    // This is a bitmap of which banks are currently selected
    output [`GENX_BANK_COUNT-1:0] bank_select

);
`include "../includes/sys_params.vh"

genvar i;

// This is the number of general registers we're going to simulate
localparam REGISTER_COUNT = 4;

// Convert a register byte address to a register index
wire[31:0] index = address >> 2;

// This is an array of 32-bit "host registers"
reg[31:0] host_reg[0:REGISTER_COUNT-1];

// This stores the bank-select bits *in little-endian*
reg[31:0] qspi_bank_en_reg;


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
// rdata always contains the data contained by the register at "address"
//=============================================================================
always @* begin
    
    if (address == QSPI_BANK_EN_REG)
        rdata = qspi_bank_en_reg;

    else if (index < REGISTER_COUNT)
        rdata = host_reg[index];

    else
        rdata = swap_endian(address);
end
//=============================================================================



//=============================================================================
// This block manages writes to the bank registers
//=============================================================================
for (i=0; i<REGISTER_COUNT; i=i+1) begin
    always @(posedge clk) begin

        // During reset, clear the host registers to 0
        if (resetn == 0)
            host_reg[i] <= 0;

        // If we've been told to write data to this particlar register...
        else if (write_strobe && index == i)
            host_reg[i] <= wdata;
    end        
end
//=============================================================================


//=============================================================================
// This block manages writes to the QSPI_BANK_EN register
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0)
        qspi_bank_en_reg <= 0;

    else if (write_strobe && address == QSPI_BANK_EN_REG)
        qspi_bank_en_reg <= wdata;
end
//=============================================================================


// The "bank_select" port is the big-endian version of qspi_bank_en_reg
assign bank_select = swap_endian(qspi_bank_en_reg);

endmodule

