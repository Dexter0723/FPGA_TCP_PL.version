//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
//Date        : Wed Oct  7 16:31:08 2026
//Host        : Dexter0723 running 64-bit major release  (build 9200)
//Command     : generate_target design_1.bd
//Design      : design_1
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "design_1,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=design_1,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=1,numReposBlks=1,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "design_1.hwdef" *) 
module design_1
   (M_AXIS_0_tdata,
    M_AXIS_0_tlast,
    M_AXIS_0_tready,
    M_AXIS_0_tvalid,
    S_AXIS_0_tdata,
    S_AXIS_0_tlast,
    S_AXIS_0_tready,
    S_AXIS_0_tvalid,
    m_axis_aclk_0,
    s_axis_aclk_0,
    s_axis_aresetn_0);
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_0 TDATA" *) (* X_INTERFACE_MODE = "Master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_0, CLK_DOMAIN design_1_m_axis_aclk_0, FREQ_HZ 100000000, HAS_TKEEP 0, HAS_TLAST 1, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 1, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) output [7:0]M_AXIS_0_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_0 TLAST" *) output M_AXIS_0_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_0 TREADY" *) input M_AXIS_0_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_0 TVALID" *) output M_AXIS_0_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_0 TDATA" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_0, CLK_DOMAIN design_1_s_axis_aclk_0, FREQ_HZ 100000000, HAS_TKEEP 0, HAS_TLAST 1, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 1, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) input [7:0]S_AXIS_0_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_0 TLAST" *) input S_AXIS_0_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_0 TREADY" *) output S_AXIS_0_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_0 TVALID" *) input S_AXIS_0_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.M_AXIS_ACLK_0 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.M_AXIS_ACLK_0, ASSOCIATED_BUSIF M_AXIS_0, CLK_DOMAIN design_1_m_axis_aclk_0, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input m_axis_aclk_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.S_AXIS_ACLK_0 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.S_AXIS_ACLK_0, ASSOCIATED_BUSIF S_AXIS_0, ASSOCIATED_RESET s_axis_aresetn_0, CLK_DOMAIN design_1_s_axis_aclk_0, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input s_axis_aclk_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.S_AXIS_ARESETN_0 RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.S_AXIS_ARESETN_0, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input s_axis_aresetn_0;

  wire [7:0]M_AXIS_0_tdata;
  wire M_AXIS_0_tlast;
  wire M_AXIS_0_tready;
  wire M_AXIS_0_tvalid;
  wire [7:0]S_AXIS_0_tdata;
  wire S_AXIS_0_tlast;
  wire S_AXIS_0_tready;
  wire S_AXIS_0_tvalid;
  wire m_axis_aclk_0;
  wire s_axis_aclk_0;
  wire s_axis_aresetn_0;

  design_1_axis_data_fifo_0_0 axis_data_fifo_0
       (.m_axis_aclk(m_axis_aclk_0),
        .m_axis_tdata(M_AXIS_0_tdata),
        .m_axis_tlast(M_AXIS_0_tlast),
        .m_axis_tready(M_AXIS_0_tready),
        .m_axis_tvalid(M_AXIS_0_tvalid),
        .s_axis_aclk(s_axis_aclk_0),
        .s_axis_aresetn(s_axis_aresetn_0),
        .s_axis_tdata(S_AXIS_0_tdata),
        .s_axis_tlast(S_AXIS_0_tlast),
        .s_axis_tready(S_AXIS_0_tready),
        .s_axis_tvalid(S_AXIS_0_tvalid));
endmodule
