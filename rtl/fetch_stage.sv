/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: fetch_stage.sv
 */



module fetch_stage (
    input logic clk,
    input logic rst,

    // Memory interface
    wishbone_interface.master wb,

    //  Output data
    output logic [31:0] instruction_reg_out,
    output logic [31:0] program_counter_reg_out,

    // Pipeline control
    output pipeline_status::forwards_t  status_forwards_out,
    input  pipeline_status::backwards_t status_backwards_in,
    input  logic [31:0] jump_address_backwards_in
);

logic [31:0] pc_reg;
logic [31:0] instruction_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        pc_reg <= constants::RESET_ADDRESS;
        instruction_reg <= 32'b0;
        status_forwards_out <= pipeline_status::BUBBLE;
    end
    else begin

        // 1. PC update (ONLY depends on backward status)
        case (status_backwards_in)
            pipeline_status::JUMP:
                pc_reg <= jump_address_backwards_in;

            pipeline_status::STALL:
                ; // hold

            pipeline_status::READY:
                pc_reg <= pc_reg + 4;
        endcase

        // 2. Instruction update
        if (wb.ack && status_backwards_in == pipeline_status::READY) begin
            instruction_reg <= wb.dat_miso;
        end

        // 3. Status update (priority: err > jump > stall > ready)
        if (wb.err) begin
            status_forwards_out <= pipeline_status::FETCH_FAULT;
        end
        else begin
            case (status_backwards_in)
                pipeline_status::JUMP:
                    status_forwards_out <= pipeline_status::BUBBLE;

                pipeline_status::STALL:
                    ; // hold

                pipeline_status::READY:
                    status_forwards_out <= pipeline_status::VALID;
            endcase
        end
    end
end

always_comb begin 

    wb.adr=pc_reg;
    wb.cyc=1'b1;
    wb.stb=1'b1;
    wb.we=1'b0;
    wb.sel=4'b1111;

    instruction_reg_out = instruction_reg;
    program_counter_reg_out = pc_reg;
 
    
end




endmodule
