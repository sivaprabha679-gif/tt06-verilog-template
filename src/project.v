```verilog
//==============================================================================
// World-Scan Gaming NPU (v1.0)
// Target: SkyWater 130nm ASIC (sky130_fd_sc_hd)
// Tiny Tapeout 06/07 Silicon Submission
// Area Budget: 160µm × 225µm (~3000 gates)
// Clock Target: 50-100 MHz
// Power Target: 22.4W with clock gating
//==============================================================================

`default_nettype none

module tt_um_world_scan (
input wire [7:0] ui_in, // 8-bit Parallel Raw Texture Data
output wire [7:0] uo_out, // 8-bit Refined AI Pixel Data
input wire [7:0] uio_in, // Bidirectional Input (Control signals)
output wire [7:0] uio_out, // Bidirectional Output (Status signals)
output wire [7:0] uio_oe, // Bidirectional Enable (output enable)
input wire ena, // Enable signal
input wire clk, // 50-100 MHz clock
input wire rst_n // Active-low reset
);

//==========================================================================
// PINOUT CONFIGURATION
//==========================================================================
// Control Inputs (uio_in):
// [3] = Power Sense (clock gating enable)
// [2] = AA Enable (Anti-Aliasing toggle)
// [1] = Weight Sync (load new AI weights)
// [0] = Reserved
//
// Status Outputs (uio_out):
// [1] = Refinement Overflow flag
// [0] = Power LED (active when processing)
// [7:2] = Reserved (tied low)

wire power_sense = uio_in[3];
wire aa_enable = uio_in[2];
wire weight_sync = uio_in[1];

// Configure bidirectional pins as outputs for status
assign uio_oe = 8'b0000_0011; // Only bits [1:0] are outputs

//==========================================================================
// CLOCK GATING LOGIC (Power Target: 22.4W)
//==========================================================================
// Only tick internal logic when power_sense is active
reg gated_clk_en;
wire gated_clk;

always @(posedge clk or negedge rst_n) begin
if (!rst_n)
gated_clk_en <= 1'b0;
else
gated_clk_en <= power_sense & ena;
end

// Clock gating cell (synthesizer will infer ICG - Integrated Clock Gate)
assign gated_clk = clk & gated_clk_en;

//==========================================================================
// AI WEIGHTING CORE
//==========================================================================
// 8-bit LLM weights register for dynamic texture refinement scaling
reg [7:0] llm_weights;

always @(posedge clk or negedge rst_n) begin
if (!rst_n)
llm_weights <= 8'd128; // Default: 0.5 scaling (128/256)
else if (weight_sync && gated_clk_en)
llm_weights <= ui_in; // Load new weights from input
end

//==========================================================================
// 4-STAGE PIPELINE: Fetch → Compare → Refine → Smooth
//==========================================================================

// Stage 1: FETCH - Input texture data capture
reg [7:0] stage1_fetch;

always @(posedge gated_clk or negedge rst_n) begin
if (!rst_n)
stage1_fetch <= 8'd0;
else
stage1_fetch <= ui_in;
end

// Stage 2: COMPARE - Compute weighted difference
reg [7:0] stage2_compare;
reg [15:0] compare_product;

always @(posedge gated_clk or negedge rst_n) begin
if (!rst_n) begin
stage2_compare <= 8'd0;
compare_product <= 16'd0;
end else begin
// 8-bit fixed-point multiplication: texture * weight
compare_product <= stage1_fetch * llm_weights;
// Bit-shift for precision (>> 4 = divide by 16)
stage2_compare <= compare_product[11:4]; // Extract middle 8 bits
end
end

// Stage 3: REFINE - Apply AI scaling with saturation
reg [7:0] stage3_refine;
reg overflow_flag;
wire [8:0] refine_sum; // 9-bit for overflow detection

assign refine_sum = {1'b0, stage2_compare} + {1'b0, stage1_fetch[7:1]};

always @(posedge gated_clk or negedge rst_n) begin
if (!rst_n) begin
stage3_refine <= 8'd0;
overflow_flag <= 1'b0;
end else begin
// Saturation clamping to prevent pixel overflow
if (refine_sum[8]) begin // Overflow detected
stage3_refine <= 8'hFF;
overflow_flag <= 1'b1;
end else begin
stage3_refine <= refine_sum[7:0];
overflow_flag <= 1'b0;
end
end
end

// Stage 4: SMOOTH - Anti-Aliasing filter (3-tap moving average)
reg [7:0] stage4_smooth;
reg [7:0] aa_history [0:2]; // 3-sample history buffer
wire [9:0] aa_sum; // 10-bit for averaging

assign aa_sum = {2'b0, aa_history[0]} +
{2'b0, aa_history[1]} +
{2'b0, aa_history[2]};

always @(posedge gated_clk or negedge rst_n) begin
if (!rst_n) begin
stage4_smooth <= 8'd0;
aa_history[0] <= 8'd0;
aa_history[1] <= 8'd0;
aa_history[2] <= 8'd0;
end else begin
// Shift history buffer
aa_history[2] <= aa_history[1];
aa_history[1] <= aa_history[0];
aa_history[0] <= stage3_refine;

// Apply AA filter if enabled, else pass through
if (aa_enable)
stage4_smooth <= aa_sum[9:2]; // Divide by 4 (approximate /3)
else
stage4_smooth <= stage3_refine;
end
end

//==========================================================================
// OUTPUT ASSIGNMENTS
//==========================================================================
// Refined AI Pixel Data output
assign uo_out = stage4_smooth;

// Status outputs
assign uio_out[0] = gated_clk_en; // Power LED (active indicator)
assign uio_out[1] = overflow_flag; // Refinement overflow flag
assign uio_out[7:2] = 6'b000000; // Reserved bits tied low

//==========================================================================
// FORMAL VERIFICATION ASSERTIONS (for synthesis sanity checks)
//==========================================================================
`ifdef FORMAL
// Ensure clock gating works correctly
always @(posedge clk) begin
if (rst_n && !power_sense)
assert(gated_clk_en == 1'b0);
end

// Verify saturation prevents overflow
always @(posedge clk) begin
if (rst_n && overflow_flag)
assert(stage3_refine == 8'hFF);
end
`endif

endmodule

`default_nettype wire
```

