/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: decode_stage.sv
 */



module decode_stage (
    input logic clk,
    input logic rst,

    // Inputs
    input logic [31:0] instruction_in,
    input logic [31:0] program_counter_in,
    input forwarding::t exe_forwarding_in,
    input forwarding::t mem_forwarding_in,
    input forwarding::t wb_forwarding_in,

    // Output Registers
    output logic [31:0] rs1_data_reg_out,
    output logic [31:0] rs2_data_reg_out,
    output logic [31:0] program_counter_reg_out,
    output instruction::t instruction_reg_out,

    // Pipeline control
    input pipeline_status::forwards_t status_forwards_in,
    output pipeline_status::forwards_t status_forwards_out,
    input pipeline_status::backwards_t status_backwards_in,
    output pipeline_status::backwards_t status_backwards_out,
    input logic [31:0] jump_address_backwards_in,
    output logic [31:0] jump_address_backwards_out
);

  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic [64:0] instruction_out;
  logic [31:0] rs1_data_forwarded;
  logic [31:0] rs2_data_forwarded;
  logic [4:0] rs1_address;
  logic [4:0] rs2_address;
  logic [4:0] rd_address;

  instruction::t instruction_decoded_out;

  instruction_decoder instruction_decoder_inst (
      .instruction_in (instruction_in),
      .instruction_out(instruction_decoded_out)
  );


  assign rs1_address = instruction_decoded_out.rs1_address;
  assign rs2_address = instruction_decoded_out.rs2_address;
  assign rd_address  = instruction_decoded_out.rd_address;



  register_file register_file_inst (
      .clk(clk),
      .rst(rst),
      .read_address1(rs1_address),
      .read_data1(rs1_data),
      .read_address2(rs2_address),
      .read_data2(rs2_data),
      .write_address(rd_address),
      .write_data(wb_forwarding_in.data),
      .write_enable(write_enable_wb)
  );



  logic write_enable_wb = (wb_forwarding_in.address == instruction_decoded_out.rd_address) && wb_forwarding_in.data_valid;

  // ─── Dependency detection ───────────────────────────────────────────────────

  // Priority-encoded: EX > MEM > WB (closest writer wins)
  // rs1
  logic rs1_dep_ex, rs1_dep_mem, rs1_dep_wb;
  logic rs1_use_ex, rs1_use_mem, rs1_use_wb;

  assign rs1_dep_ex  = (exe_forwarding_in.address == rs1_address) && (rs1_address != '0);
  assign rs1_dep_mem = (mem_forwarding_in.address == rs1_address) && (rs1_address != '0);
  assign rs1_dep_wb  = (wb_forwarding_in.address == rs1_address) && (rs1_address != '0);

  // Only the closest valid writer is actually used — suppress farther ones
  assign rs1_use_ex  = rs1_dep_ex && exe_forwarding_in.data_valid;
  assign rs1_use_mem = rs1_dep_mem && mem_forwarding_in.data_valid && !rs1_use_ex;
  assign rs1_use_wb  = rs1_dep_wb && wb_forwarding_in.data_valid && !rs1_use_ex && !rs1_use_mem;

  // rs2
  logic rs2_dep_ex, rs2_dep_mem, rs2_dep_wb;
  logic rs2_use_ex, rs2_use_mem, rs2_use_wb;

  assign rs2_dep_ex  = (exe_forwarding_in.address == rs2_address) && (rs2_address != '0);
  assign rs2_dep_mem = (mem_forwarding_in.address == rs2_address) && (rs2_address != '0);
  assign rs2_dep_wb  = (wb_forwarding_in.address == rs2_address) && (rs2_address != '0);

  assign rs2_use_ex  = rs2_dep_ex && exe_forwarding_in.data_valid;
  assign rs2_use_mem = rs2_dep_mem && mem_forwarding_in.data_valid && !rs2_use_ex;
  assign rs2_use_wb  = rs2_dep_wb && wb_forwarding_in.data_valid && !rs2_use_ex && !rs2_use_mem;

  // ─── Stall logic ────────────────────────────────────────────────────────────

  // Stall only when there's a dependency on a stage that can't forward yet.
  // WB is never a stall source — register file bypass always works by WB.
  logic stall_required;
  assign stall_required =
    (rs1_dep_ex  && !exe_forwarding_in.data_valid) ||
    (rs2_dep_ex  && !exe_forwarding_in.data_valid) ||
    (rs1_dep_mem && !mem_forwarding_in.data_valid) ||
    (rs2_dep_mem && !mem_forwarding_in.data_valid);

  // ─── Forwarding mux ─────────────────────────────────────────────────────────


  assign rs1_data_forwarded = rs1_use_ex  ? exe_forwarding_in.data :
                            rs1_use_mem ? mem_forwarding_in.data :
                            rs1_use_wb  ? wb_forwarding_in.data  : rs1_data;

  assign rs2_data_forwarded = rs2_use_ex  ? exe_forwarding_in.data :
                            rs2_use_mem ? mem_forwarding_in.data :
                            rs2_use_wb  ? wb_forwarding_in.data  : rs2_data;


  //The backwards signals need to travel through all stages in the same clock cycle — with zero delay  
  // =====================
  // COMBINATORIAL — backwards signals
  // =====================
  assign status_backwards_out = (stall_required) 
                               ? pipeline_status::STALL 
                               : status_backwards_in; // passthrough

  assign jump_address_backwards_out = (status_backwards_in == pipeline_status::JUMP) 
                               ? jump_address_backwards_in 
                               : '0;

  // =====================
  // SEQUENTIAL — forwards signals and data registers
  // =====================
  always_ff @(posedge clk) begin

    if (rst) begin
      rs1_data_reg_out        <= '0;
      rs2_data_reg_out        <= '0;
      program_counter_reg_out <= constants::RESET_ADDRESS;
      instruction_reg_out     <= '0;
      status_forwards_out     <= pipeline_status::BUBBLE;
    end else begin

      case (status_backwards_in)

        pipeline_status::JUMP: begin
          status_forwards_out <= pipeline_status::BUBBLE;  // flush
        end

        pipeline_status::STALL: begin
          // hold — do nothing, registers keep values
        end

        pipeline_status::READY: begin

          if (stall_required) begin
            // forwarding data not ready — insert bubble
            status_forwards_out <= pipeline_status::BUBBLE;

          end else begin

            case (status_forwards_in)

              pipeline_status::FETCH_FAULT: begin
                status_forwards_out     <= pipeline_status::FETCH_FAULT;
                program_counter_reg_out <= program_counter_in;
              end
              //the input it received from the previous stage is invalid, so no signals will be propogate further
              pipeline_status::BUBBLE: begin
                status_forwards_out <= pipeline_status::BUBBLE;
              end

              pipeline_status::VALID: begin
                if (instruction_decoded_out.op == op::EBREAK) begin
                  status_forwards_out     <= pipeline_status::EBREAK;
                  program_counter_reg_out <= program_counter_in;

                  // Spec §5.2: "ECALL and EBREAK are valid, but handled like errors.
                  // Therefore, the status needs to be set accordingly."
                end else if (instruction_decoded_out.op == op::ECALL) begin
                  status_forwards_out     <= pipeline_status::ECALL;
                  program_counter_reg_out <= program_counter_in;

                end else if (instruction_decoded_out.op == op::ILLEGAL) begin
                  status_forwards_out     <= pipeline_status::ILLEGAL_INSTRUCTION;
                  program_counter_reg_out <= program_counter_in;

                end else begin
                  status_forwards_out     <= pipeline_status::VALID;
                  program_counter_reg_out <= program_counter_in;
                  instruction_reg_out     <= instruction_decoded_out;
                  rs1_data_reg_out        <= rs1_data_forwarded;
                  rs2_data_reg_out        <= rs2_data_forwarded;
                end
              end

              default: begin
                status_forwards_out <= pipeline_status::BUBBLE;
              end

            endcase
          end
        end

        default: begin
          status_forwards_out <= pipeline_status::BUBBLE;
        end

      endcase
    end
  end


endmodule
