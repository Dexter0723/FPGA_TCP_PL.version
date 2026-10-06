`timescale 1ns / 1ps

// Pure-PL, single-connection TCP server optimized for continuous PL-to-PC
// transmission on a controlled 1 GbE LAN. It implements a 32-slot sliding
// transmit window. Each slot occupies 2 KiB of BRAM and carries up to one
// 1460-byte TCP segment, for 64 KiB of physical TX storage.
module tcp_engine #(
           parameter [47:0] LOCAL_MAC  = 48'h00_11_22_33_44_55,
           parameter [31:0] LOCAL_IP   = {8'd192, 8'd168, 8'd1, 8'd10},
           parameter [15:0] LOCAL_PORT = 16'd5000,
           parameter [31:0] INITIAL_SEQUENCE = 32'h1234_5678,
           parameter [15:0] MSS = 16'd1460,
           parameter [15:0] LOCAL_WINDOW = 16'd46720,
           parameter [31:0] RTO_CYCLES = 32'd125_000_000
       )(
           input  wire        clk,
           input  wire        rst_n,

           input  wire        gmii_rx_dv,
           input  wire [7:0]  gmii_rxd,

           // FPGA -> PC
           input  wire        app_tx_valid,
           input  wire [7:0]  app_tx_data,
           input  wire        app_tx_flush,
           output wire        app_tx_ready,

           // PC -> FPGA
           output reg  [7:0]  app_rx_data,
           output reg         app_rx_valid,
           output reg         app_rx_last,
           input  wire        app_rx_ready,

           output wire        tx_request,
           input  wire        tx_grant,
           output wire        gmii_tx_en,
           output wire [7:0]  gmii_txd,
           output wire        tx_busy,
           output wire        tx_done,

           output wire        connected
       );

localparam [2:0] TCP_LISTEN      = 3'd0;
localparam [2:0] TCP_SYN_RCVD    = 3'd1;
localparam [2:0] TCP_ESTABLISHED = 3'd2;
localparam [2:0] TCP_LAST_ACK    = 3'd3;

localparam SLOT_COUNT      = 32;
localparam SLOT_INDEX_W    = 5;
localparam SLOT_ADDR_W     = 11;
localparam RAM_ADDR_W      = SLOT_INDEX_W + SLOT_ADDR_W;

wire        rx_event_valid;
wire        rx_checksum_ok;
wire [47:0] rx_remote_mac;
wire [31:0] rx_remote_ip;
wire [15:0] rx_remote_port;
wire [31:0] rx_seq_num;
wire [31:0] rx_ack_num;
wire [7:0]  rx_flags;
wire [15:0] rx_window;
wire [15:0] rx_payload_length;

wire                       rx_payload_wr_en;
wire [SLOT_ADDR_W-1:0]     rx_payload_wr_addr;
wire [7:0]                 rx_payload_wr_data;

wire                       rx_ram_write_en;
reg  [SLOT_ADDR_W-1:0]     rx_ram_read_addr;
wire [7:0]                 rx_ram_read_data;

reg                        rx_packet_busy;
reg  [15:0]                rx_packet_length;
reg  [15:0]                rx_packet_index;
reg                        rx_packet_fin;

reg  [1:0]                 rx_output_state;

localparam [1:0] RX_OUT_IDLE = 2'd0;
localparam [1:0] RX_OUT_WAIT = 2'd1;
localparam [1:0] RX_OUT_LOAD = 2'd2;
localparam [1:0] RX_OUT_HOLD = 2'd3;

wire                       app_rx_fire;
wire [15:0]                advertised_rx_window;

reg [2:0]   tcp_state;
reg [47:0]  remote_mac_reg;
reg [31:0]  remote_ip_reg;
reg [15:0]  remote_port_reg;
reg [31:0]  snd_una;
reg [31:0]  snd_nxt;
reg [31:0]  rcv_nxt;
reg [15:0]  peer_window;
reg [15:0]  ip_identification;

reg         control_pending;
reg [7:0]   control_flags;
reg [31:0]  control_seq;
reg [31:0]  control_ack;
reg         control_advances_seq;
reg         control_is_retransmit;
reg [31:0]  fin_sequence;

reg         retransmit_pending;
reg [31:0]  rto_counter;
reg [2:0]   duplicate_ack_count;
reg         session_clear;

reg [15:0]  descriptor_length [0:SLOT_COUNT-1];
reg [31:0]  descriptor_sum    [0:SLOT_COUNT-1];
reg [31:0]  descriptor_seq    [0:SLOT_COUNT-1];
reg         descriptor_sent   [0:SLOT_COUNT-1];

reg [SLOT_INDEX_W-1:0] descriptor_write_index;
reg [SLOT_INDEX_W-1:0] descriptor_send_index;
reg [SLOT_INDEX_W-1:0] descriptor_una_index;
reg [SLOT_INDEX_W:0]   descriptor_count;
reg [SLOT_INDEX_W:0]   unsent_count;

reg [SLOT_ADDR_W-1:0]  app_write_offset;
reg [31:0]              app_segment_sum;
reg [7:0]               app_high_byte;
reg                     app_pair_pending;

wire                    app_accept;
wire                    segment_complete;
wire [31:0]             completed_segment_sum;
wire [15:0]             completed_segment_length;
wire [RAM_ADDR_W-1:0]   ram_write_addr;
wire                    ram_write_en;
wire [RAM_ADDR_W-1:0]   ram_read_addr;
wire [7:0]              ram_read_data;

reg                     retire_active;
reg [31:0]              retire_ack_target;
reg [1:0]               retire_phase;
reg [SLOT_INDEX_W-1:0]  retire_check_index;
reg [31:0]              retire_check_end;
reg                     retire_check_sent;
reg                     retire_match;
wire                    retire_commit;

wire [31:0]             bytes_in_flight;
wire [15:0]             next_descriptor_length;
reg                     new_data_candidate;
wire                    retransmit_candidate;
wire                    control_candidate;
wire                    select_control;
wire                    select_retransmit;
wire                    select_new_data;
wire                    tx_fire;

localparam [1:0] LAUNCH_CONTROL    = 2'd0;
localparam [1:0] LAUNCH_RETRANSMIT = 2'd1;
localparam [1:0] LAUNCH_NEW_DATA   = 2'd2;

// Packet-launch pipeline.  Descriptor RAM selection and TCP frame setup are
// separated by this register bank so neither operation has to complete in the
// same 125 MHz clock period.
reg                     launch_valid;
reg [1:0]               launch_kind;
reg [7:0]               launch_flags;
reg [31:0]              launch_sequence;
reg [31:0]              launch_acknowledgment;
reg [15:0]              launch_payload_length;
reg [31:0]              launch_payload_sum;
reg [RAM_ADDR_W-1:0]    launch_payload_start;
reg [SLOT_INDEX_W-1:0]  launch_descriptor_index;
reg                     launch_advances_seq;
reg                     launch_control_is_retransmit;

integer i;

function sequence_leq;
    input [31:0] left_value;
    input [31:0] right_value;
    reg signed [31:0] difference;
    begin
        difference = left_value - right_value;
        sequence_leq = (difference <= 0);
    end
endfunction

function sequence_after;
    input [31:0] left_value;
    input [31:0] right_value;
    reg signed [31:0] difference;
    begin
        difference = left_value - right_value;
        sequence_after = (difference > 0);
    end
endfunction

assign connected = (tcp_state == TCP_ESTABLISHED);

assign app_rx_fire = app_rx_valid && app_rx_ready;
assign rx_ram_write_en = rx_payload_wr_en && !rx_packet_busy;
assign advertised_rx_window = rx_packet_busy ? 16'd0 : MSS;

assign app_tx_ready = connected && !session_clear && (descriptor_count < SLOT_COUNT);
assign app_accept = app_tx_valid && app_tx_ready;
assign segment_complete = app_accept && ((app_write_offset == (MSS - 1'b1)) || app_tx_flush);
assign completed_segment_length = {5'd0, app_write_offset} + 1'b1;
assign completed_segment_sum = app_pair_pending
       ? (app_segment_sum + {16'd0, app_high_byte, app_tx_data})
       : (app_segment_sum + {16'd0, app_tx_data, 8'd0});

assign ram_write_en   = app_accept;
assign ram_write_addr = {descriptor_write_index, app_write_offset};

assign retire_commit = retire_active && (retire_phase == 2'd2) && retire_match;

assign bytes_in_flight = snd_nxt - snd_una;
assign next_descriptor_length = descriptor_length[descriptor_send_index];

assign control_candidate = control_pending;
assign retransmit_candidate = retransmit_pending &&
       (descriptor_count != 0) &&
       descriptor_sent[descriptor_una_index];
assign select_control    = control_candidate;
assign select_retransmit = !control_candidate && retransmit_candidate;
assign select_new_data   = !control_candidate && !retransmit_candidate &&
       new_data_candidate;
assign tx_request = launch_valid && !tx_busy && !session_clear;
assign tx_fire = tx_request && tx_grant;

tcp_rx #(
           .LOCAL_MAC   (LOCAL_MAC),
           .LOCAL_IP    (LOCAL_IP),
           .LOCAL_PORT  (LOCAL_PORT),
           .MAX_PAYLOAD (MSS)
       ) u_tcp_rx (
           .clk             (clk),
           .rst_n           (rst_n),
           .gmii_rx_dv      (gmii_rx_dv),
           .gmii_rxd        (gmii_rxd),

           .event_valid     (rx_event_valid),
           .checksum_ok     (rx_checksum_ok),
           .remote_mac      (rx_remote_mac),
           .remote_ip       (rx_remote_ip),
           .remote_port     (rx_remote_port),
           .seq_num         (rx_seq_num),
           .ack_num         (rx_ack_num),
           .flags           (rx_flags),
           .window_size     (rx_window),
           .payload_length  (rx_payload_length),

           .payload_wr_en   (rx_payload_wr_en),
           .payload_wr_addr (rx_payload_wr_addr),
           .payload_wr_data (rx_payload_wr_data)
       );

// One TCP receive packet buffer: 2048 x 8-bit
tcp_ram #(
            .ADDR_WIDTH (SLOT_ADDR_W)
        ) u_tcp_rx_ram (
            .clk     (clk),
            .wr_en   (rx_ram_write_en),
            .wr_addr (rx_payload_wr_addr),
            .wr_data (rx_payload_wr_data),
            .rd_addr (rx_ram_read_addr),
            .rd_data (rx_ram_read_data)
        );

tcp_tx #(
           .LOCAL_MAC      (LOCAL_MAC),
           .LOCAL_IP       (LOCAL_IP),
           .LOCAL_PORT     (LOCAL_PORT),
           .RAM_ADDR_WIDTH (RAM_ADDR_W)
       ) u_tcp_tx (
           .clk                    (clk),
           .rst_n                  (rst_n),
           .tx_start               (tx_fire),
           .remote_mac             (remote_mac_reg),
           .remote_ip              (remote_ip_reg),
           .remote_port            (remote_port_reg),
           .sequence_number        (launch_sequence),
           .acknowledgment_number  (launch_acknowledgment),
           .tcp_flags              (launch_flags),
           .local_window           (advertised_rx_window),
           .payload_length         (launch_payload_length),
           .payload_start          (launch_payload_start),
           .payload_sum            (launch_payload_sum),
           .ip_identification      (ip_identification),
           .payload_rd_addr        (ram_read_addr),
           .payload_rd_data        (ram_read_data),
           .busy                   (tx_busy),
           .tx_done                (tx_done),
           .gmii_tx_en             (gmii_tx_en),
           .gmii_txd               (gmii_txd)
       );

tcp_ram #(
            .ADDR_WIDTH (RAM_ADDR_W)
        ) u_tcp_tx_ram (
            .clk     (clk),
            .wr_en   (ram_write_en),
            .wr_addr (ram_write_addr),
            .wr_data (app_tx_data),
            .rd_addr (ram_read_addr),
            .rd_data (ram_read_data)
        );

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tcp_state                  <= TCP_LISTEN;
        remote_mac_reg             <= 48'd0;
        remote_ip_reg              <= 32'd0;
        remote_port_reg            <= 16'd0;
        snd_una                    <= INITIAL_SEQUENCE;
        snd_nxt                    <= INITIAL_SEQUENCE;
        rcv_nxt                    <= 32'd0;
        peer_window                <= LOCAL_WINDOW;
        ip_identification          <= 16'd1;
        control_pending            <= 1'b0;
        control_flags              <= 8'd0;
        control_seq                <= 32'd0;
        control_ack                <= 32'd0;
        control_advances_seq       <= 1'b0;
        control_is_retransmit      <= 1'b0;
        fin_sequence               <= 32'd0;
        retransmit_pending         <= 1'b0;
        rto_counter                <= 32'd0;
        duplicate_ack_count        <= 3'd0;
        session_clear              <= 1'b1;
        descriptor_write_index     <= {SLOT_INDEX_W{1'b0}};
        descriptor_send_index      <= {SLOT_INDEX_W{1'b0}};
        descriptor_una_index       <= {SLOT_INDEX_W{1'b0}};
        descriptor_count           <= {(SLOT_INDEX_W+1){1'b0}};
        unsent_count               <= {(SLOT_INDEX_W+1){1'b0}};
        app_write_offset           <= {SLOT_ADDR_W{1'b0}};
        app_segment_sum            <= 32'd0;
        app_high_byte              <= 8'd0;
        app_pair_pending           <= 1'b0;
        retire_active              <= 1'b0;
        retire_ack_target          <= 32'd0;
        retire_phase               <= 2'd0;
        retire_check_index         <= {SLOT_INDEX_W{1'b0}};
        retire_check_end           <= 32'd0;
        retire_check_sent          <= 1'b0;
        retire_match               <= 1'b0;
        new_data_candidate          <= 1'b0;
        launch_valid               <= 1'b0;
        launch_kind                <= LAUNCH_CONTROL;
        launch_flags               <= 8'd0;
        launch_sequence            <= 32'd0;
        launch_acknowledgment      <= 32'd0;
        launch_payload_length      <= 16'd0;
        launch_payload_sum         <= 32'd0;
        launch_payload_start       <= {RAM_ADDR_W{1'b0}};
        launch_descriptor_index    <= {SLOT_INDEX_W{1'b0}};
        launch_advances_seq        <= 1'b0;
        launch_control_is_retransmit <= 1'b0;
        rx_packet_busy   <= 1'b0;
        rx_packet_length <= 16'd0;
        rx_packet_index  <= 16'd0;
        rx_packet_fin    <= 1'b0;
        rx_ram_read_addr <= {SLOT_ADDR_W{1'b0}};
        rx_output_state  <= RX_OUT_IDLE;

        app_rx_data      <= 8'd0;
        app_rx_valid     <= 1'b0;
        app_rx_last      <= 1'b0;

        for (i = 0; i < SLOT_COUNT; i = i + 1)
            descriptor_sent[i] <= 1'b0;
    end
    else begin
        session_clear <= 1'b0;

        // Deliver one verified packet to application logic.
        if (session_clear) begin
            rx_packet_busy   <= 1'b0;
            rx_packet_length <= 16'd0;
            rx_packet_index  <= 16'd0;
            rx_packet_fin    <= 1'b0;
            rx_ram_read_addr <= {SLOT_ADDR_W{1'b0}};
            rx_output_state  <= RX_OUT_IDLE;

            app_rx_data      <= 8'd0;
            app_rx_valid     <= 1'b0;
            app_rx_last      <= 1'b0;
        end
        else begin
            case (rx_output_state)
                RX_OUT_IDLE: begin
                    app_rx_valid <= 1'b0;
                    app_rx_last  <= 1'b0;
                end

                // tcp_tx_ram 是 synchronous-read RAM。
                RX_OUT_WAIT: begin
                    app_rx_valid    <= 1'b0;
                    rx_output_state <= RX_OUT_LOAD;
                end

                RX_OUT_LOAD: begin
                    app_rx_data     <= rx_ram_read_data;
                    app_rx_valid    <= 1'b1;
                    app_rx_last     <=
                    (rx_packet_index ==
                     (rx_packet_length - 1'b1));
                    rx_output_state <= RX_OUT_HOLD;
                end

                RX_OUT_HOLD: begin
                    if (app_rx_fire) begin
                        app_rx_valid <= 1'b0;

                        if (app_rx_last) begin
                            rx_packet_busy  <= 1'b0;
                            rx_packet_index <= 16'd0;
                            rx_output_state <= RX_OUT_IDLE;

                            // Window-update ACK：通知 PC 可以繼續送。
                            control_pending       <= 1'b1;
                            control_seq           <= snd_nxt;
                            control_ack           <= rcv_nxt;
                            control_is_retransmit <= 1'b0;

                            if (rx_packet_fin) begin
                                control_flags        <= 8'h11;
                                control_advances_seq <= 1'b1;
                                fin_sequence         <= snd_nxt;
                                tcp_state            <= TCP_LAST_ACK;
                            end
                            else begin
                                control_flags        <= 8'h10;
                                control_advances_seq <= 1'b0;
                            end
                        end
                        else begin
                            rx_packet_index  <= rx_packet_index + 1'b1;
                            rx_ram_read_addr <= rx_packet_index + 1'b1;
                            rx_output_state  <= RX_OUT_WAIT;
                        end
                    end
                end

                default: begin
                    rx_packet_busy  <= 1'b0;
                    app_rx_valid    <= 1'b0;
                    app_rx_last     <= 1'b0;
                    rx_output_state <= RX_OUT_IDLE;
                end
            endcase
        end

        // Register the window decision before it controls the large launch
        // register bank.  Descriptor pointers cannot advance while tx_busy,
        // so the one-cycle-old decision is stable whenever it is consumed.
        if (session_clear) begin
            new_data_candidate <= 1'b0;
        end
        else begin
            new_data_candidate <= connected && (unsent_count != 0) &&
                               ((bytes_in_flight + next_descriptor_length) <=
                                ((peer_window < LOCAL_WINDOW)
                                 ? peer_window : LOCAL_WINDOW));
        end

        // Application-side segment formation and streaming payload checksum.
        if (session_clear) begin
            descriptor_write_index <= {SLOT_INDEX_W{1'b0}};
            descriptor_send_index  <= {SLOT_INDEX_W{1'b0}};
            descriptor_una_index   <= {SLOT_INDEX_W{1'b0}};
            descriptor_count       <= {(SLOT_INDEX_W+1){1'b0}};
            unsent_count           <= {(SLOT_INDEX_W+1){1'b0}};
            app_write_offset       <= {SLOT_ADDR_W{1'b0}};
            app_segment_sum        <= 32'd0;
            app_pair_pending       <= 1'b0;
            retire_active          <= 1'b0;
            retire_phase           <= 2'd0;
            retire_match           <= 1'b0;
            retransmit_pending     <= 1'b0;
            launch_valid           <= 1'b0;
            for (i = 0; i < SLOT_COUNT; i = i + 1)
                descriptor_sent[i] <= 1'b0;
        end
        else begin
            if (app_accept) begin
                if (app_pair_pending) begin
                    app_segment_sum  <= app_segment_sum +
                                     {16'd0, app_high_byte, app_tx_data};
                    app_pair_pending <= 1'b0;
                end
                else begin
                    app_high_byte    <= app_tx_data;
                    app_pair_pending <= 1'b1;
                end

                if (segment_complete) begin
                    descriptor_length[descriptor_write_index] <= completed_segment_length;
                    descriptor_sum[descriptor_write_index]    <= completed_segment_sum;
                    descriptor_sent[descriptor_write_index]   <= 1'b0;
                    descriptor_write_index <= descriptor_write_index + 1'b1;
                    app_write_offset   <= {SLOT_ADDR_W{1'b0}};
                    app_segment_sum    <= 32'd0;
                    app_pair_pending   <= 1'b0;
                end
                else begin
                    app_write_offset <= app_write_offset + 1'b1;
                end
            end

            if (retire_active) begin
                case (retire_phase)
                    2'd0: begin
                        if (descriptor_count != 0) begin
                            retire_check_index <= descriptor_una_index;
                            retire_check_end   <=
                            descriptor_seq[descriptor_una_index] +
                            descriptor_length[descriptor_una_index];
                            retire_check_sent  <=
                            descriptor_sent[descriptor_una_index];
                            retire_phase <= 2'd1;
                        end
                        else begin
                            retire_active <= 1'b0;
                        end
                    end
                    2'd1: begin
                        retire_match <= retire_check_sent &&
                        sequence_leq(retire_check_end,
                                     retire_ack_target);
                        retire_phase <= 2'd2;
                    end
                    default: begin
                        if (retire_match) begin
                            descriptor_sent[retire_check_index] <= 1'b0;
                            descriptor_una_index <= retire_check_index + 1'b1;
                            retire_phase <= 2'd0;
                        end
                        else begin
                            retire_active <= 1'b0;
                            retire_phase  <= 2'd0;
                        end
                    end
                endcase
            end
            else begin
                retire_phase <= 2'd0;
                retire_match <= 1'b0;
            end

            case ({segment_complete, retire_commit})
                2'b10:
                    descriptor_count <= descriptor_count + 1'b1;
                2'b01:
                    descriptor_count <= descriptor_count - 1'b1;
                default:
                    ;
            endcase

            case ({segment_complete,
                       (tx_fire && (launch_kind == LAUNCH_NEW_DATA))})
                2'b10:
                    unsent_count <= unsent_count + 1'b1;
                2'b01:
                    unsent_count <= unsent_count - 1'b1;
                default:
                    ;
            endcase

            // Select and register one complete launch descriptor.  Waiting
            // for the shared Ethernet arbiter does not change this snapshot.
            if (!launch_valid && !tx_busy) begin
                if (select_control) begin
                    launch_valid          <= 1'b1;
                    launch_kind           <= LAUNCH_CONTROL;
                    launch_flags          <= control_flags;
                    launch_sequence       <= control_seq;
                    launch_acknowledgment <= control_ack;
                    launch_payload_length <= 16'd0;
                    launch_payload_sum    <= 32'd0;
                    launch_payload_start  <= {RAM_ADDR_W{1'b0}};
                    launch_advances_seq   <= control_advances_seq;
                    launch_control_is_retransmit <= control_is_retransmit;
                end
                else if (select_retransmit) begin
                    launch_valid          <= 1'b1;
                    launch_kind           <= LAUNCH_RETRANSMIT;
                    launch_flags          <= 8'h18;
                    launch_sequence       <= descriptor_seq[descriptor_una_index];
                    launch_acknowledgment <= rcv_nxt;
                    launch_payload_length <= descriptor_length[descriptor_una_index];
                    launch_payload_sum    <= descriptor_sum[descriptor_una_index];
                    launch_payload_start  <= {descriptor_una_index,
                                              {SLOT_ADDR_W{1'b0}}};
                    launch_descriptor_index <= descriptor_una_index;
                    launch_advances_seq   <= 1'b0;
                    launch_control_is_retransmit <= 1'b0;
                end
                else if (select_new_data) begin
                    launch_valid          <= 1'b1;
                    launch_kind           <= LAUNCH_NEW_DATA;
                    launch_flags          <= 8'h18;
                    launch_sequence       <= snd_nxt;
                    launch_acknowledgment <= rcv_nxt;
                    launch_payload_length <= descriptor_length[descriptor_send_index];
                    launch_payload_sum    <= descriptor_sum[descriptor_send_index];
                    launch_payload_start  <= {descriptor_send_index,
                                              {SLOT_ADDR_W{1'b0}}};
                    launch_descriptor_index <= descriptor_send_index;
                    launch_advances_seq   <= 1'b0;
                    launch_control_is_retransmit <= 1'b0;
                end
            end
        end

        // A granted request starts exactly one complete Ethernet frame.
        if (tx_fire) begin
            launch_valid      <= 1'b0;
            ip_identification <= ip_identification + 1'b1;
            if (launch_kind == LAUNCH_CONTROL) begin
                control_pending <= 1'b0;
                if (launch_advances_seq && !launch_control_is_retransmit)
                    snd_nxt <= snd_nxt + 1'b1;
            end
            else if (launch_kind == LAUNCH_RETRANSMIT) begin
                retransmit_pending    <= 1'b0;
            end
            else if (launch_kind == LAUNCH_NEW_DATA) begin
                descriptor_seq[launch_descriptor_index]  <= launch_sequence;
                descriptor_sent[launch_descriptor_index] <= 1'b1;
                descriptor_send_index <= descriptor_send_index + 1'b1;
                snd_nxt <= snd_nxt + launch_payload_length;
            end
        end

        // Retransmission timer. The controlled-LAN default is parameterized
        // so simulation and hardware can use different timeout values.
        if ((snd_nxt != snd_una) &&
                ((tcp_state == TCP_SYN_RCVD) ||
                 (tcp_state == TCP_ESTABLISHED) ||
                 (tcp_state == TCP_LAST_ACK))) begin
            if (rto_counter >= (RTO_CYCLES - 1'b1)) begin
                rto_counter <= 32'd0;
                if ((tcp_state == TCP_ESTABLISHED) &&
                        (descriptor_count != 0)) begin
                    retransmit_pending <= 1'b1;
                end
                else if ((tcp_state == TCP_SYN_RCVD) && !control_pending) begin
                    control_pending       <= 1'b1;
                    control_flags         <= 8'h12;
                    control_seq           <= INITIAL_SEQUENCE;
                    control_ack           <= rcv_nxt;
                    control_advances_seq  <= 1'b1;
                    control_is_retransmit <= 1'b1;
                end
                else if ((tcp_state == TCP_LAST_ACK) && !control_pending) begin
                    control_pending       <= 1'b1;
                    control_flags         <= 8'h11;
                    control_seq           <= fin_sequence;
                    control_ack           <= rcv_nxt;
                    control_advances_seq  <= 1'b1;
                    control_is_retransmit <= 1'b1;
                end
            end
            else begin
                rto_counter <= rto_counter + 1'b1;
            end
        end
        else begin
            rto_counter <= 32'd0;
        end

        // Receive-side connection processing.
        if (rx_event_valid && rx_checksum_ok) begin
            case (tcp_state)
                TCP_LISTEN: begin
                    if (rx_flags[1] && !rx_flags[4] && !rx_flags[2]) begin
                        remote_mac_reg        <= rx_remote_mac;
                        remote_ip_reg         <= rx_remote_ip;
                        remote_port_reg       <= rx_remote_port;
                        rcv_nxt               <= rx_seq_num + 1'b1;
                        snd_una               <= INITIAL_SEQUENCE;
                        snd_nxt               <= INITIAL_SEQUENCE;
                        peer_window           <= rx_window;
                        control_pending       <= 1'b1;
                        control_flags         <= 8'h12;
                        control_seq           <= INITIAL_SEQUENCE;
                        control_ack           <= rx_seq_num + 1'b1;
                        control_advances_seq  <= 1'b1;
                        control_is_retransmit <= 1'b0;
                        retransmit_pending    <= 1'b0;
                        duplicate_ack_count   <= 3'd0;
                        session_clear         <= 1'b1;
                        tcp_state             <= TCP_SYN_RCVD;
                    end
                end

                TCP_SYN_RCVD: begin
                    if (rx_flags[2]) begin
                        tcp_state     <= TCP_LISTEN;
                        session_clear <= 1'b1;
                    end
                    else if ((rx_remote_ip == remote_ip_reg) &&
                             (rx_remote_port == remote_port_reg)) begin
                        if (rx_flags[4] &&
                                (rx_ack_num == (INITIAL_SEQUENCE + 1'b1))) begin
                            snd_una             <= rx_ack_num;
                            peer_window         <= rx_window;
                            rto_counter         <= 32'd0;
                            tcp_state           <= TCP_ESTABLISHED;
                        end
                        else if (rx_flags[1]) begin
                            control_pending       <= 1'b1;
                            control_flags         <= 8'h12;
                            control_seq           <= INITIAL_SEQUENCE;
                            control_ack           <= rcv_nxt;
                            control_advances_seq  <= 1'b1;
                            control_is_retransmit <= 1'b1;
                        end
                    end
                end

                TCP_ESTABLISHED: begin
                    if ((rx_remote_ip == remote_ip_reg) &&
                            (rx_remote_port == remote_port_reg)) begin
                        if (rx_flags[2]) begin
                            tcp_state     <= TCP_LISTEN;
                            session_clear <= 1'b1;
                        end
                        else begin
                            if (rx_flags[4]) begin
                                peer_window <= rx_window;
                                if (sequence_after(rx_ack_num, snd_una) &&
                                        sequence_leq(rx_ack_num, snd_nxt)) begin
                                    snd_una             <= rx_ack_num;
                                    retire_ack_target   <= rx_ack_num;
                                    retire_active       <= 1'b1;
                                    retire_phase        <= 2'd0;
                                    retire_match        <= 1'b0;
                                    rto_counter         <= 32'd0;
                                    duplicate_ack_count <= 3'd0;
                                end
                                else if ((rx_ack_num == snd_una) &&
                                         (snd_nxt != snd_una)) begin
                                    if (duplicate_ack_count == 3'd2) begin
                                        retransmit_pending   <= 1'b1;
                                        duplicate_ack_count  <= 3'd3;
                                    end
                                    else if (duplicate_ack_count < 3'd3) begin
                                        duplicate_ack_count <= duplicate_ack_count + 1'b1;
                                    end
                                end
                            end

                            if (((rx_payload_length != 16'd0) || rx_flags[0]) &&
                                    (rx_seq_num == rcv_nxt) &&
                                    ((rx_payload_length == 16'd0) ||
                                     ((!rx_packet_busy) &&
                                      (rx_payload_length <= MSS)))) begin

                                // 有 payload：資料已經在 RX packet RAM。
                                if (rx_payload_length != 16'd0) begin
                                    rx_packet_busy   <= 1'b1;
                                    rx_packet_length <= rx_payload_length;
                                    rx_packet_index  <= 16'd0;
                                    rx_packet_fin    <= rx_flags[0];
                                    rx_ram_read_addr <= {SLOT_ADDR_W{1'b0}};
                                    rx_output_state  <= RX_OUT_WAIT;
                                    app_rx_valid     <= 1'b0;
                                    app_rx_last      <= 1'b0;

                                    rcv_nxt <= rcv_nxt + rx_payload_length +
                                    (rx_flags[0] ? 1'b1 : 1'b0);

                                    // 先 ACK 已寫入 packet RAM 的資料。
                                    // rx_packet_busy 會使 advertised window 變成 0。
                                    control_pending       <= 1'b1;
                                    control_flags         <= 8'h10;
                                    control_seq           <= snd_nxt;
                                    control_ack           <= rcv_nxt +
                                    rx_payload_length +
                                    (rx_flags[0] ? 1'b1 : 1'b0);
                                    control_advances_seq  <= 1'b0;
                                    control_is_retransmit <= 1'b0;
                                end

                                //no payload，only FIN。
                                else if (rx_flags[0]) begin
                                    rcv_nxt <= rcv_nxt + 1'b1;

                                    control_pending       <= 1'b1;
                                    control_flags         <= 8'h11;
                                    control_seq           <= snd_nxt;
                                    control_ack           <= rcv_nxt + 1'b1;
                                    control_advances_seq  <= 1'b1;
                                    control_is_retransmit <= 1'b0;

                                    fin_sequence <= snd_nxt;
                                    tcp_state    <= TCP_LAST_ACK;
                                end
                            end
                        end
                    end
                end

                TCP_LAST_ACK: begin
                    if (rx_flags[2]) begin
                        tcp_state     <= TCP_LISTEN;
                        session_clear <= 1'b1;
                    end
                    else if (rx_flags[4] &&
                             (rx_ack_num == snd_nxt)) begin
                        snd_una       <= rx_ack_num;
                        tcp_state     <= TCP_LISTEN;
                        session_clear <= 1'b1;
                    end
                end

                default: begin
                    tcp_state     <= TCP_LISTEN;
                    session_clear <= 1'b1;
                end
            endcase
        end
    end
end

endmodule
