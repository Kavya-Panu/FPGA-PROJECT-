`timescale 1ns/1ps
`default_nettype none
module symbol_match_engine #(
    parameter integer TABLE_SIZE = 8,
    parameter integer INDEX_WIDTH = (TABLE_SIZE <= 1) ? 1 : $clog2(TABLE_SIZE)
) (
    input wire clk, input wire rst,
    input wire cfg_we, input wire [INDEX_WIDTH-1:0] cfg_index,
    input wire cfg_enable, input wire [63:0] cfg_symbol,
    input wire [31:0] cfg_buy_price, cfg_sell_price,
    output reg cfg_error,
    input wire tick_valid, input wire [63:0] tick_symbol,
    input wire [31:0] tick_sequence, tick_price, tick_quantity,
    output reg event_valid, output reg [1:0] event_action,
    output reg [INDEX_WIDTH-1:0] event_index,
    output reg [63:0] event_symbol,
    output reg [31:0] event_sequence, event_price, event_quantity,
    output reg [31:0] symbol_misses, holds
);
    reg [TABLE_SIZE-1:0] enabled;
    reg [63:0] symbols [0:TABLE_SIZE-1];
    reg [31:0] buy_prices [0:TABLE_SIZE-1], sell_prices [0:TABLE_SIZE-1];
    reg match_valid;
    reg [TABLE_SIZE-1:0] match_mask, buy_mask, sell_mask;
    reg [63:0] match_symbol;
    reg [31:0] match_sequence, match_price, match_quantity;
    reg found;
    reg [INDEX_WIDTH-1:0] selected_index;
    reg [1:0] selected_action;
    integer i, j;
    always @* begin
        found = 0; selected_index = 0; selected_action = 0;
        // Duplicate symbols are deterministic: lowest enabled index wins.
        for (j=0; j<TABLE_SIZE; j=j+1) begin
            if (!found && match_mask[j]) begin
                found = 1;
                selected_index = j[INDEX_WIDTH-1:0];
                if (buy_mask[j]) selected_action = 2'd1;
                else if (sell_mask[j]) selected_action = 2'd2;
            end
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            enabled <= 0; cfg_error <= 0;
            match_valid <= 0; match_mask <= 0; buy_mask <= 0; sell_mask <= 0;
            match_symbol <= 0; match_sequence <= 0; match_price <= 0; match_quantity <= 0;
            event_valid <= 0; event_action <= 0; event_index <= 0;
            event_symbol <= 0; event_sequence <= 0; event_price <= 0; event_quantity <= 0;
            symbol_misses <= 0; holds <= 0;
            for (i=0; i<TABLE_SIZE; i=i+1) begin
                symbols[i] <= 0; buy_prices[i] <= 0; sell_prices[i] <= 0;
            end
        end else begin
            cfg_error <= 0;
            if (cfg_we) begin
                if (int'(cfg_index) >= TABLE_SIZE ||
                    (cfg_enable && cfg_buy_price >= cfg_sell_price)) cfg_error <= 1;
                else begin
                    enabled[cfg_index] <= cfg_enable;
                    symbols[cfg_index] <= cfg_symbol;
                    buy_prices[cfg_index] <= cfg_buy_price;
                    sell_prices[cfg_index] <= cfg_sell_price;
                end
            end
            match_valid <= tick_valid;
            if (tick_valid) begin
                match_symbol <= tick_symbol; match_sequence <= tick_sequence;
                match_price <= tick_price; match_quantity <= tick_quantity;
                // All comparators are independent hardware, evaluated together.
                // A configuration write on this same edge takes effect next edge.
                for (i=0; i<TABLE_SIZE; i=i+1) begin
                    match_mask[i] <= enabled[i] && symbols[i] == tick_symbol;
                    buy_mask[i] <= tick_price <= buy_prices[i];
                    sell_mask[i] <= tick_price >= sell_prices[i];
                end
            end
            event_valid <= 0;
            if (match_valid) begin
                if (!found) symbol_misses <= symbol_misses + 1'b1;
                else if (selected_action == 0) holds <= holds + 1'b1;
                else begin
                    event_valid <= 1;
                    event_action <= selected_action; event_index <= selected_index;
                    event_symbol <= match_symbol; event_sequence <= match_sequence;
                    event_price <= match_price; event_quantity <= match_quantity;
                end
            end
        end
    end
endmodule
`default_nettype wire
