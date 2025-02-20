


// We want the QSPI interface signals broken out for debug
`define ADD_DEBUG_PORTS

// Tell "qspi_fields.vh" that we are a receiver of QSPI requests
`define QSPI_FRONT_END

// Fetch the lengths of the QSPI related fields
`include "qspi_field_widths.vh"

module qspi_manager  
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
    output[`QSPI_RSP_WIDTH-1:0] qspi_rsp_out
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
// This function stuffs each bit of an input byte into the bottom bit 
// of each nybble of a 32-bit word
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
