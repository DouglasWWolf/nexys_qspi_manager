
//================================================================================================
//    Date      Vers   Who  Changes
// -----------------------------------------------------------------------------------------------
// 22-Feb-2025  1.0.0  DWW  Initial creation
//================================================================================================
localparam VERSION_MAJOR = 1;
localparam VERSION_MINOR = 0;
localparam VERSION_BUILD = 0;
localparam VERSION_RCAND = 0;

localparam VERSION_DAY   = 22;
localparam VERSION_MONTH = 2;
localparam VERSION_YEAR  = 2025;

localparam RTL_TYPE      = 22225;
localparam RTL_SUBTYPE   = 0;


/*
    ***************   TTD   ***************   

     rework the ltc-2656 simulator to use modern clocking on SCK and CS
     rename simulator stuff to gxsim
     create read bulk SMEM
     create write bulk SMEM
     add spi_clk_div to the dac driver
*/


/*
    After final falling SCK edge, do we need a delay before releasing CS?
*/