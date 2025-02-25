
//=============================================================================
// Module: gxsim_bank_reg_smem
//
// Simulates the GenX bank-registers, SMEM buffer, and SMEM
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================
`include "../includes/sys_defines.vh"

module gxsim_bank_reg_smem 
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

    // This is high if this bank is should listen to write instructions
    input bank_select
);

// Include system-wide localparam definitions
`include "../includes/sys_params.vh"

// "Write-enable".  When this is high, we need to write data
wire we = write_strobe & bank_select;

localparam FOO_REG = 16;
reg[31:0] foo_reg;

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
    
    if (address == FOO_REG)
        rdata = foo_reg;
    else
        rdata = swap_endian(address);
end
//=============================================================================


//=============================================================================
// This block manages "FOO_REG" and is a template that SHOULD BE REMOVED!!!
//=============================================================================
always @(posedge clk) begin

    // During reset, clear the bank registers to 0
    if (resetn == 0)
        foo_reg <= 0;

    // If we've been told to write data to a register, make it so
    else if (we && address == FOO_REG) begin
        foo_reg <= wdata;
    end
end
//=============================================================================


endmodule

