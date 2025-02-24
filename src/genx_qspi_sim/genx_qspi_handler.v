//=============================================================================
// Module: genx_qspi_handler
//
// Handles read and write requests that were received from simulated QSPI
//
// Date         Who  What
//-----------------------------------------------------------------------------
// 23-Feb-2025  DWW  Initial Creation
//=============================================================================

module genx_qspi_handler 
(

    input   clk, resetn,

    // These go high for one cycle to serve as ILA triggers
    output       dbg_notify_write,
    output       dbg_notify_read,  

    input      [  9:0] sck_counts,   // Count of the rising edges of SCK
    input      [  7:0] opcode,       // Opcode that arrived on MOSI
    input      [ 31:0] address,      // Address that arrived on MOSI
    input      [  1:0] chip_select,  // Which chip-selects are active?   
    input      [255:0] wdata_h,      // Data to be written to a register or SMEM
    input      [255:0] wdata_l,      // Data to be written to a register or SMEM
    output reg [255:0] rdata_h,      // Data read from registers or SMEM
    output reg [255:0] rdata_l,      // Data read from registers or SMEM

    input        async_notify_read,   // Rising edge = chip_select, address, and opcode
                                      // have arrived

    input        async_notify_write   // Chip-select has de-asserted
);

// There are 8 32-bit words in wdata_h, wdata_l, rdata_h, and rdata_l
localparam DW = 8;

// Bring in the QSPI opcodes
`include "../includes/genx_qspi_opcodes.vh"

// Definitions of the valid chip-select statess
localparam CS_HOST = 2'b10;
localparam CS_BANK = 2'b01;

// These are synchronous versions of the async input portss
wire notify_read, notify_write;

// This is data that's being read from the "host" register
wire[31:0] host_rdata;

//=============================================================================
// Keep track of the prior state of the "notify signals" and use those states
// to perform edge detection
//=============================================================================
reg prior_notify_read, prior_notify_write;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    prior_notify_read  <= notify_read;
    prior_notify_write <= notify_write;
end
wire notify_read_rising  = (prior_notify_read  == 0) & (notify_read  == 1);
wire notify_write_rising = (prior_notify_write == 0) & (notify_write == 1);
//=============================================================================

//=============================================================================
// Sync async_notify_read into notify_read
//=============================================================================
xpm_cdc_single # (.SRC_INPUT_REG(0)) cdc_notify_read
(
    .src_in  (async_notify_read),   
    .dest_out(notify_read), 
    .dest_clk(clk), 
    .src_clk ()  
);
//=============================================================================


//=============================================================================
// Sync async_notify_write into notify_write
//=============================================================================
xpm_cdc_single # (.SRC_INPUT_REG(0)) cdc_notify_write
(
    .src_in  (async_notify_write),   
    .dest_out(notify_write), 
    .dest_clk(clk), 
    .src_clk ()  
);
//=============================================================================


//=============================================================================
// Assign output ports for debugging via ILA
//=============================================================================
assign dbg_notify_write = notify_write_rising;
assign dbg_notify_read  = notify_read_rising;
//=============================================================================





always @(posedge clk) begin

    rdata_h <= 0;
    rdata_l <= 0;

    if (chip_select == CS_HOST) begin
        if (opcode == GENX_QSPI_OPCODE_READ_SINGLE) begin
            rdata_h <= {(host_rdata[31:0]), {DW-1{32'b0}}};
        end
    end

end



// This will strobe high when it's time to write to "host" register
wire write_host_reg = notify_write_rising
                    & (chip_select == CS_HOST)
                    & (opcode      == GENX_QSPI_OPCODE_WRITE_SINGLE);


//=============================================================================
// This is a simulator for the GenX "host" registers
//=============================================================================
gxsim_host_reg host_registers
(
    .clk            (clk),
    .resetn         (resetn),
    .address        (address),
    .wdata          (wdata_h[255 -: 32]),
    .write_strobe   (write_host_reg),
    .rdata          (host_rdata),
    .bank_select    ()
);
//=============================================================================

endmodule