`timescale 1ns/1ps
`default_nettype none
// Basys 3 demonstration at the on-board 100 MHz clock. No external Ethernet.
module basys3_demo_top #(
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer AUTO_CYCLES = 50000000,
    parameter integer POWER_ON_CYCLES = 256
) (
    input wire clk, input wire btnC, input wire btnU,
    input wire [3:0] sw,
    output reg [15:0] led,
    output reg [6:0] seg, output wire dp, output reg [3:0] an
);
    localparam integer DW = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam integer AW = (AUTO_CYCLES <= 1) ? 1 : $clog2(AUTO_CYCLES);
    localparam integer PW = (POWER_ON_CYCLES <= 1) ? 1 : $clog2(POWER_ON_CYCLES+1);
    (* ASYNC_REG = "TRUE" *) reg reset_meta = 0, reset_sync = 0;
    (* ASYNC_REG = "TRUE" *) reg [4:0] ui_meta = 0, ui_sync = 0;
    reg [PW-1:0] power_count = 0;
    wire rst = int'(power_count) < POWER_ON_CYCLES || reset_sync;
    always @(posedge clk) begin
        reset_meta <= btnU; reset_sync <= reset_meta;
        ui_meta <= {sw,btnC}; ui_sync <= ui_meta;
        if (int'(power_count) < POWER_ON_CYCLES) power_count <= power_count + 1'b1;
    end
    reg [4:0] stable_ui;
    reg [4:0] ui_candidate;
    reg [DW-1:0] stable_count;
    reg button_previous;
    wire send_button = stable_ui[0] && !button_previous;
    always @(posedge clk) begin
        if (rst) begin stable_ui <= 0; ui_candidate <= 0; stable_count <= 0; button_previous <= 0; end
        else begin
            button_previous <= stable_ui[0];
            if (ui_sync != ui_candidate) begin ui_candidate <= ui_sync; stable_count <= 0; end
            else if (ui_candidate == stable_ui) stable_count <= 0;
            else if (int'(stable_count) == DEBOUNCE_CYCLES-1) begin
                stable_ui <= ui_candidate; stable_count <= 0;
            end else stable_count <= stable_count + 1'b1;
        end
    end

    localparam [2:0] INIT=0, IDLE=1, SEND=2, DRAIN=3;
    reg [2:0] state;
    reg [3:0] beat;
    reg [2:0] scenario;
    reg [3:0] drain_count;
    reg [AW-1:0] auto_count;
    reg [31:0] before_holds, before_misses, before_rejects;
    reg [4:0] outcome; // bit 0 BUY, 1 SELL, 2 HOLD, 3 MISS, 4 REJECT.
    reg error_seen;
    reg [31:0] action_count;
    reg [26:0] heartbeat;
    wire [63:0] rx_data;
    wire rx_valid = state == SEND;
    wire rx_last = beat == 8;
    wire [7:0] rx_keep = !rx_last ? 8'hff : (scenario == 7 ? 8'h01 : 8'h03);
    wire rx_bad = scenario == 6 && rx_last;
    wire cfg_error, event_valid;
    wire [1:0] event_action;
    wire [2:0] event_index;
    wire [63:0] event_symbol;
    wire [31:0] event_sequence, event_price, event_quantity;
    wire [31:0] rx_frames, accepted_frames, rejected_frames, symbol_misses,
                holds, events_enqueued, events_dropped;
    wire [4:0] fifo_level;
    wire rx_ready;
    basys3_packet_rom packets (.address({scenario,beat}),.data(rx_data));
    tick_to_trade core (
        .clk(clk),.rst(rst),.s_axis_tdata(rx_data),.s_axis_tkeep(rx_keep),
        .s_axis_tvalid(rx_valid),.s_axis_tlast(rx_last),.s_axis_tuser(rx_bad),.s_axis_tready(rx_ready),
        .cfg_we(state==INIT),.cfg_index(3'd0),.cfg_enable(1'b1),
        .cfg_symbol(64'h4141504c20202020),.cfg_buy_price(32'd1000000),.cfg_sell_price(32'd1100000),
        .cfg_error(cfg_error),.m_event_valid(event_valid),.m_event_ready(1'b1),
        .m_event_action(event_action),.m_event_index(event_index),.m_event_symbol(event_symbol),
        .m_event_sequence(event_sequence),.m_event_price(event_price),.m_event_quantity(event_quantity),
        .fifo_level(fifo_level),.rx_frames(rx_frames),.accepted_frames(accepted_frames),
        .rejected_frames(rejected_frames),.symbol_misses(symbol_misses),.holds(holds),
        .events_enqueued(events_enqueued),.events_dropped(events_dropped)
    );
    always @(posedge clk) begin
        if (rst) begin
            state<=INIT; beat<=0; scenario<=0; drain_count<=0; auto_count<=0;
            before_holds<=0; before_misses<=0; before_rejects<=0;
            outcome<=0; error_seen<=0; action_count<=0; heartbeat<=0;
        end else begin
            heartbeat<=heartbeat+1'b1;
            if (cfg_error || events_dropped != 0) error_seen<=1;
            if (event_valid) begin
                action_count<=action_count+1'b1;
                if (event_action==1) outcome[0]<=1;
                if (event_action==2) outcome[1]<=1;
            end
            case (state)
                INIT: state<=IDLE;
                IDLE: begin
                    if (send_button || (stable_ui[4] && int'(auto_count)==AUTO_CYCLES-1)) begin
                        scenario<=stable_ui[3:1]; beat<=0; state<=SEND;
                        before_holds<=holds; before_misses<=symbol_misses;
                        before_rejects<=rejected_frames; outcome<=0; auto_count<=0;
                    end else if (stable_ui[4]) auto_count<=auto_count+1'b1;
                    else auto_count<=0;
                end
                SEND: begin
                    if (rx_ready) begin
                        if (rx_last) begin state<=DRAIN; drain_count<=0; end
                        else beat<=beat+1'b1;
                    end
                end
                DRAIN: begin
                    if (drain_count==10) begin
                        outcome[2]<=holds!=before_holds;
                        outcome[3]<=symbol_misses!=before_misses;
                        outcome[4]<=rejected_frames!=before_rejects;
                        state<=IDLE;
                    end else drain_count<=drain_count+1'b1;
                end
                default: state<=INIT;
            endcase
        end
    end
    // Register human-visible outputs at the I/O boundary. This also prevents
    // combinational display decode from becoming a register-to-pin critical path.
    always @(posedge clk) begin
        if (rst) led<=0;
        else led<={heartbeat[26],rx_frames[6:0],(state!=INIT),
                   (state==SEND || state==DRAIN),error_seen,outcome};
    end

    reg [15:0] scan_count;
    reg [3:0] digit;
    reg [6:0] seg_next;
    reg [3:0] an_next;
    always @(posedge clk) begin
        if (rst) scan_count<=0;
        else scan_count<=scan_count+1'b1;
    end
    always @* begin
        case (scan_count[15:14])
            0: begin an_next=4'b1110; digit=action_count[3:0]; end
            1: begin an_next=4'b1101; digit=action_count[7:4]; end
            2: begin an_next=4'b1011; digit=action_count[11:8]; end
            default: begin an_next=4'b0111; digit=action_count[15:12]; end
        endcase
        case (digit)
            0: seg_next=7'b1000000; 1: seg_next=7'b1111001; 2: seg_next=7'b0100100; 3: seg_next=7'b0110000;
            4: seg_next=7'b0011001; 5: seg_next=7'b0010010; 6: seg_next=7'b0000010; 7: seg_next=7'b1111000;
            8: seg_next=7'b0000000; 9: seg_next=7'b0010000; 10: seg_next=7'b0001000; 11: seg_next=7'b0000011;
            12: seg_next=7'b1000110; 13: seg_next=7'b0100001; 14: seg_next=7'b0000110; default: seg_next=7'b0001110;
        endcase
    end
    always @(posedge clk) begin
        if (rst) begin seg<=7'b1111111; an<=4'b1111; end
        else begin seg<=seg_next; an<=an_next; end
    end
    assign dp=1'b1;
endmodule
`default_nettype wire
