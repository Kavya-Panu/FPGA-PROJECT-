`timescale 1ns/1ps
`default_nettype none
module tick_to_trade #(
    parameter [15:0] UDP_PORT = 16'd1234,
    parameter integer TABLE_SIZE = 8,
    parameter integer FIFO_DEPTH = 16,
    parameter integer INDEX_WIDTH = (TABLE_SIZE <= 1) ? 1 : $clog2(TABLE_SIZE),
    parameter integer LEVEL_WIDTH = $clog2(FIFO_DEPTH+1)
) (
    input wire clk, input wire rst,
    input wire [63:0] s_axis_tdata, input wire [7:0] s_axis_tkeep,
    input wire s_axis_tvalid, s_axis_tlast, s_axis_tuser,
    output wire s_axis_tready,
    input wire cfg_we, input wire [INDEX_WIDTH-1:0] cfg_index,
    input wire cfg_enable, input wire [63:0] cfg_symbol,
    input wire [31:0] cfg_buy_price, cfg_sell_price, output wire cfg_error,
    output wire m_event_valid, input wire m_event_ready,
    output wire [1:0] m_event_action, output wire [INDEX_WIDTH-1:0] m_event_index,
    output wire [63:0] m_event_symbol,
    output wire [31:0] m_event_sequence, m_event_price, m_event_quantity,
    output wire [LEVEL_WIDTH-1:0] fifo_level,
    output wire [31:0] rx_frames, accepted_frames, rejected_frames,
    output wire [31:0] symbol_misses, holds, events_enqueued, events_dropped
);
    localparam integer EVENT_WIDTH = 162 + INDEX_WIDTH;
    wire tick_valid;
    wire [63:0] tick_symbol;
    wire [31:0] tick_sequence, tick_price, tick_quantity;
    wire event_valid;
    wire [1:0] event_action;
    wire [INDEX_WIDTH-1:0] event_index;
    wire [63:0] event_symbol;
    wire [31:0] event_sequence, event_price, event_quantity;
    wire [EVENT_WIDTH-1:0] event_data;
    market_data_parser #(.UDP_PORT(UDP_PORT)) parser (
        .clk(clk), .rst(rst), .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tlast(s_axis_tlast), .s_axis_tuser(s_axis_tuser),
        .s_axis_tready(s_axis_tready), .tick_valid(tick_valid), .tick_symbol(tick_symbol),
        .tick_sequence(tick_sequence), .tick_price(tick_price), .tick_quantity(tick_quantity),
        .rx_frames(rx_frames), .accepted_frames(accepted_frames), .rejected_frames(rejected_frames)
    );
    symbol_match_engine #(.TABLE_SIZE(TABLE_SIZE), .INDEX_WIDTH(INDEX_WIDTH)) matcher (
        .clk(clk), .rst(rst), .cfg_we(cfg_we), .cfg_index(cfg_index), .cfg_enable(cfg_enable),
        .cfg_symbol(cfg_symbol), .cfg_buy_price(cfg_buy_price), .cfg_sell_price(cfg_sell_price),
        .cfg_error(cfg_error), .tick_valid(tick_valid), .tick_symbol(tick_symbol),
        .tick_sequence(tick_sequence), .tick_price(tick_price), .tick_quantity(tick_quantity),
        .event_valid(event_valid), .event_action(event_action), .event_index(event_index),
        .event_symbol(event_symbol), .event_sequence(event_sequence), .event_price(event_price),
        .event_quantity(event_quantity), .symbol_misses(symbol_misses), .holds(holds)
    );
    event_fifo #(.WIDTH(EVENT_WIDTH), .DEPTH(FIFO_DEPTH)) queue (
        .clk(clk), .rst(rst), .s_valid(event_valid),
        .s_data({event_action,event_index,event_symbol,event_sequence,event_price,event_quantity}),
        .m_valid(m_event_valid), .m_ready(m_event_ready), .m_data(event_data),
        .level(fifo_level), .enqueued(events_enqueued), .dropped(events_dropped)
    );
    assign {m_event_action,m_event_index,m_event_symbol,m_event_sequence,
            m_event_price,m_event_quantity} = event_data;
endmodule
`default_nettype wire
