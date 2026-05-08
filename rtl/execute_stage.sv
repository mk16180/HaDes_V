/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: execute_stage.sv
 */



module execute_stage (
    input logic clk,
    input logic rst,

    // Inputs
    input logic [31:0] rs1_data_in,
    input logic [31:0] rs2_data_in,
    input instruction::t instruction_in,
    input logic [31:0] program_counter_in,

    // Outputs
    output logic [31:0] source_data_reg_out,  //
    output logic [31:0] rd_data_reg_out,  //
    output instruction::t instruction_reg_out,  //
    output logic [31:0] program_counter_reg_out,  //
    output logic [31:0] next_program_counter_reg_out,  //
    output forwarding::t forwarding_out,  //

    // Pipeline control
    input pipeline_status::forwards_t status_forwards_in,
    output pipeline_status::forwards_t status_forwards_out,
    input pipeline_status::backwards_t status_backwards_in,
    output pipeline_status::backwards_t status_backwards_out,  //
    input logic [31:0] jump_address_backwards_in,
    output logic [31:0] jump_address_backwards_out  //
);

  logic [31:0] source_data;
  logic [31:0] rd_data;

  logic branch_taken;
  logic branch_inst;

  logic [31:0] branch_target_address;
  logic [31:0] addr;

  logic fetch_misaligned;

  // -----------------------------------------
  // Branch Detection + Target Calculation
  // -----------------------------------------
  always_comb begin
    branch_inst = 1'b0;
    branch_target_address = 32'b0;

    if (instruction_in.op inside {
        op::BEQ, op::BNE, op::BLT, op::BGE,
        op::BLTU, op::BGEU, op::JAL, op::JALR
    }) begin
      branch_inst = 1'b1;

      if (instruction_in.op == op::JALR) begin
        branch_target_address = (rs1_data_in + instruction_in.immediate) & ~32'd1;
      end else if (branch_taken) begin
        branch_target_address = program_counter_in + instruction_in.immediate;
      end

    end

  end

  // -----------------------------------------
  // Backward Control Logic
  // -----------------------------------------
  always_comb begin
    status_backwards_out       = status_backwards_in;
    jump_address_backwards_out = jump_address_backwards_in;

    if (status_backwards_in == pipeline_status::READY) begin
      if (branch_taken) begin
        status_backwards_out = pipeline_status::JUMP;
        jump_address_backwards_out = branch_target_address;
      end
    end
  end

  //----------
  // Forwarding Logic
  //----------
  always_comb begin

    if (status_forwards_in == pipeline_status::VALID && instruction_in.rd_address != 5'd0) begin
      forwarding_out.data_valid = 1'b1;
      forwarding_out.data = rd_data;
      forwarding_out.address = instruction_in.rd_address;
    end else begin
      forwarding_out.data_valid = 1'b0;
      forwarding_out.data = 32'b0;
      forwarding_out.address = 5'b0;
    end

  end

  // -----------------------------------------
  // Fetch Misaligned Detection
  // -----------------------------------------

  assign fetch_misaligned = next_program_counter_reg_out[1:0] != 2'b00;



  // -----------------------------------------
  // Execute Logic
  // -----------------------------------------
  always_comb begin
    rd_data      = 32'b0;
    source_data  = 32'b0;
    branch_taken = 1'b0;

    case (instruction_in.op)

      // R-Type
      op::ADD:  rd_data = rs1_data_in + rs2_data_in;
      op::SUB:  rd_data = rs1_data_in - rs2_data_in;
      op::SLL:  rd_data = rs1_data_in << rs2_data_in[4:0];
      op::SLT:  rd_data = ($signed(rs1_data_in) < $signed(rs2_data_in)) ? 32'd1 : 32'd0;
      op::SLTU: rd_data = (rs1_data_in < rs2_data_in) ? 32'd1 : 32'd0;
      op::XOR:  rd_data = rs1_data_in ^ rs2_data_in;
      op::SRL:  rd_data = rs1_data_in >> rs2_data_in[4:0];
      op::SRA:  rd_data = $signed(rs1_data_in) >>> rs2_data_in[4:0];
      op::OR:   rd_data = rs1_data_in | rs2_data_in;
      op::AND:  rd_data = rs1_data_in & rs2_data_in;

      // I-Type
      op::ADDI: rd_data = rs1_data_in + instruction_in.immediate;
      op::SLLI: rd_data = rs1_data_in << instruction_in.immediate[4:0];
      op::SLTI:
      rd_data = ($signed(rs1_data_in) < $signed(instruction_in.immediate)) ? 32'd1 : 32'd0;

      op::SLTIU: rd_data = (rs1_data_in < instruction_in.immediate) ? 32'd1 : 32'd0;
      op::XORI:  rd_data = rs1_data_in ^ instruction_in.immediate;
      op::SRLI:  rd_data = rs1_data_in >> instruction_in.immediate[4:0];
      op::SRAI:  rd_data = $signed(rs1_data_in) >>> instruction_in.immediate[4:0];
      op::ORI:   rd_data = rs1_data_in | instruction_in.immediate;
      op::ANDI:  rd_data = rs1_data_in & instruction_in.immediate;

      // Store
      op::SB: begin
        rd_data     = rs1_data_in + instruction_in.immediate;
        source_data = rs2_data_in[7:0];
      end

      op::SH: begin
        rd_data     = rs1_data_in + instruction_in.immediate;
        source_data = rs2_data_in[15:0];
      end

      op::SW: begin
        rd_data     = rs1_data_in + instruction_in.immediate;
        source_data = rs2_data_in;
      end

      // Load
      op::LB: begin
        addr    = rs1_data_in + instruction_in.immediate;
        rd_data = addr[7:0];
      end

      op::LH: begin
        addr    = rs1_data_in + instruction_in.immediate;
        rd_data = addr[15:0];
      end

      op::LW: rd_data = rs1_data_in + instruction_in.immediate;

      op::LBU: begin
        addr    = rs1_data_in + instruction_in.immediate;
        rd_data = addr[7:0];
      end

      op::LHU: begin
        addr    = rs1_data_in + instruction_in.immediate;
        rd_data = addr[15:0];
      end

      // Branch
      op::BEQ:  branch_taken = (rs1_data_in == rs2_data_in);
      op::BNE:  branch_taken = (rs1_data_in != rs2_data_in);
      op::BLT:  branch_taken = ($signed(rs1_data_in) < $signed(rs2_data_in));
      op::BGE:  branch_taken = ($signed(rs1_data_in) >= $signed(rs2_data_in));
      op::BLTU: branch_taken = (rs1_data_in < rs2_data_in);
      op::BGEU: branch_taken = (rs1_data_in >= rs2_data_in);

      // Jump
      op::JAL: begin
        branch_taken = 1'b1;
        rd_data      = program_counter_in + 4;
      end

      op::JALR: begin
        branch_taken = 1'b1;
        rd_data      = program_counter_in + 4;
      end

      // U-Type
      op::LUI:   rd_data = instruction_in.immediate << 12;
      op::AUIPC: rd_data = program_counter_in + (instruction_in.immediate << 12);

      default: rd_data = 32'b0;
    endcase
  end

  always_ff @(posedge clk) begin

    if (rst) begin
      program_counter_reg_out      <= constants::RESET_ADDRESS;
      source_data_reg_out          <= 32'b0;
      rd_data_reg_out              <= 32'b0;
      instruction_reg_out          <= '0;
      status_forwards_out          <= pipeline_status::BUBBLE;
      forwarding_out               <= '0;
      next_program_counter_reg_out <= 32'b0;

    end else begin

      case (status_backwards_in)
        pipeline_status::JUMP: begin
          status_forwards_out <= pipeline_status::BUBBLE;  // flush
        end
        pipeline_status::STALL: begin
          // hold — do nothing, registers keep values
        end
        pipeline_status::READY: begin

          if (status_forwards_in inside {
                pipeline_status::FETCH_FAULT,
                pipeline_status::ILLEGAL_INSTRUCTION,
                pipeline_status::ECALL,
                pipeline_status::EBREAK
                }) begin
            status_forwards_out     <= status_forwards_in;
            program_counter_reg_out <= program_counter_in;

          end else if (status_forwards_in == pipeline_status::BUBBLE) begin
            status_forwards_out <= pipeline_status::BUBBLE;
            program_counter_reg_out <= program_counter_in;

          end else if (status_forwards_in == pipeline_status::VALID) begin

            if (fetch_misaligned) begin
              status_forwards_out     <= pipeline_status::FETCH_MISALIGNED;
              program_counter_reg_out <= program_counter_in;

            end else if (branch_taken) begin
              status_forwards_out <= pipeline_status::BUBBLE;  // flush
              next_program_counter_reg_out <= branch_target_address;
              program_counter_reg_out <= program_counter_in;

            end else begin
              status_forwards_out <= pipeline_status::VALID;
              program_counter_reg_out <= program_counter_in;
              instruction_reg_out <= instruction_in;
              rd_data_reg_out <= rd_data;
              source_data_reg_out <= source_data;
              next_program_counter_reg_out <= (program_counter_in + 4);
            end

          end
        end

        default: begin
          status_forwards_out <= pipeline_status::BUBBLE;
        end

      endcase


    end

  end

endmodule
