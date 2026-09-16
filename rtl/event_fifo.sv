`timescale 1ns/1ps
`default_nettype none
// Small register FIFO. Drop newest on full, preserving previously queued events.
module event_fifo #(
    parameter integer WIDTH = 165,
    parameter integer DEPTH = 16,
    parameter integer PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter integer COUNT_WIDTH = $clog2(DEPTH+1)
) (
    input wire clk, input wire rst,
    input wire s_valid, input wire [WIDTH-1:0] s_data,
    output wire m_valid, input wire m_ready, output wire [WIDTH-1:0] m_data,
    output reg [COUNT_WIDTH-1:0] level,
    output reg [31:0] enqueued, dropped
);
    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
    wire pop = m_valid && m_ready;
    wire push = s_valid && (int'(level) < DEPTH || pop);
    assign m_valid = level != 0;
    assign m_data = m_valid ? memory[rd_ptr] : {WIDTH{1'b0}};
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0; rd_ptr <= 0; level <= 0; enqueued <= 0; dropped <= 0;
        end else begin
            if (push) begin
                memory[wr_ptr] <= s_data;
                wr_ptr <= (int'(wr_ptr) == DEPTH-1) ? {PTR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                enqueued <= enqueued + 1'b1;
            end else if (s_valid) dropped <= dropped + 1'b1;
            if (pop) rd_ptr <= (int'(rd_ptr) == DEPTH-1) ? {PTR_WIDTH{1'b0}} : rd_ptr + 1'b1;
            case ({push,pop})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
