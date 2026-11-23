////////////////////////////////////////////////////////////////////////////////
// Author: Kareem Waseem
// Course: Digital Verification using SV & UVM
//
// Description: FIFO Design
//
////////////////////////////////////////////////////////////////////////////////
import shared_pkg::*;

module FIFO(FIFO_INTERFACE.DUT fifo_1);

localparam max_fifo_addr = $clog2(FIFO_DEPTH);

reg [FIFO_WIDTH-1:0] mem [FIFO_DEPTH-1:0];

reg [max_fifo_addr-1:0] wr_ptr, rd_ptr;
reg [max_fifo_addr:0] count;

initial begin
    // BUG FIX: Internal FIFO state was not initialized at simulation start.
    // Without initialization, count and pointers could contain X values
    // before reset was applied.
    count  = 0;
    wr_ptr = 0;
    rd_ptr = 0;
end

always @(posedge fifo_1.clk or negedge fifo_1.rst_n) begin
    if (!fifo_1.rst_n) begin
        wr_ptr <= 0;
        fifo_1.wr_ack <= 0;
        fifo_1.overflow <= 0;
    end
    else begin

        if (fifo_1.wr_en && count < FIFO_DEPTH) begin
            mem[wr_ptr] <= fifo_1.data_in;
            fifo_1.wr_ack <= 1;
            wr_ptr <= wr_ptr + 1;
        end
        else begin
            fifo_1.wr_ack <= 0;
        end

        // BUG FIX: Overflow detection was previously coupled to the
        // write-operation else branch. It is now checked independently
        // whenever a write is attempted while the FIFO is full.
        if (fifo_1.full && fifo_1.wr_en)
            fifo_1.overflow <= 1;
        else
            fifo_1.overflow <= 0;

    end
end

always @(posedge fifo_1.clk or negedge fifo_1.rst_n) begin
    if (!fifo_1.rst_n) begin
        // BUG FIX: data_out was not reset in the original RTL,
        // which could leave it at an unknown value after reset.
        rd_ptr <= 0;
        fifo_1.data_out <= '0;
    end
    else if (fifo_1.rd_en && count != 0) begin
        fifo_1.data_out <= mem[rd_ptr];
        rd_ptr <= rd_ptr + 1;
    end
end

always @(posedge fifo_1.clk or negedge fifo_1.rst_n) begin
    if (!fifo_1.rst_n) begin
        count <= 0;
    end
    else begin

        // BUG FIX: The original RTL did not explicitly handle the
        // simultaneous read/write case (wr_en=1, rd_en=1).
        // Boundary cases such as simultaneous read/write when the FIFO
        // is empty or full are now handled explicitly.
        case ({fifo_1.wr_en, fifo_1.rd_en})
            2'b10:
                if (!fifo_1.full)
                    count <= count + 1;

            2'b01:
                if (!fifo_1.empty)
                    count <= count - 1;

            2'b11: begin
                if (!fifo_1.full && !fifo_1.empty)
                    count <= count;
                else if (fifo_1.empty)
                    count <= count + 1;
                else if (fifo_1.full)
                    count <= count - 1;
            end

            default: ;
        endcase
    end
end

assign fifo_1.full = (count == FIFO_DEPTH) ? 1 : 0;
assign fifo_1.empty = (count == 0) ? 1 : 0;
assign fifo_1.underflow = (fifo_1.empty && fifo_1.rd_en) ? 1 : 0;

// BUG FIX: The original RTL asserted almostfull at FIFO_DEPTH-2.
// The required behavior is to assert it when only one FIFO entry
// remains available.
assign fifo_1.almostfull = (count == FIFO_DEPTH-1) ? 1 : 0;

assign fifo_1.almostempty = (count == 1) ? 1 : 0;

// NOTE (UVM project): the SVA block that used to live here was moved to
// tb/FIFO_SVA.sv and is attached with a `bind` in FIFO_TOP.sv. RTL logic above is unchanged.

endmodule
