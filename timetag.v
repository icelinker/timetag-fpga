module timetag(
	fx2_clk,
	data_rdy, data, data_ack,
	cmd_wr, cmd_in,
	reply_rdy, reply, reply_ack, reply_end,

	clk,
	detectors,
	laser_en
);

// Clocks
input	fx2_clk;
input	clk;

// For Host->FPGA commands
input	cmd_wr;
input	[7:0] cmd_in;

// For FPGA->Host command replies
output	reply_rdy;
output	[7:0] reply;
input	reply_ack;
output	reply_end;

// For FPGA->Host data
output	data_rdy;
output	[7:0] data;
input	data_ack;

// Acquisition inputs
input	[3:0] detectors;
output	[3:0] laser_en;

// Internal command tracking signals
wire	[7:0] cmd_rdy;
wire	[7:0] cmd;
wire	[7:0] cmd_ack;
assign cmd_ack[7:6] = 0;

cmd_parser cmd_parser(
	.fx2_clk(fx2_clk),
	.clk(clk),
	.cmd_wr(cmd_wr),
	.cmd_in(cmd_in),

	.cmd_mask(cmd_rdy),
	.data(cmd),
	.data_ack(cmd_ack != 0)
);

wire	[7:0] timer_cmd;
strobe_bits_controller apdtimer_controller(
	.clk(clk),
	.mask_bit(cmd_rdy[0]),
	.data(cmd),
	.data_ack(cmd_ack[0]),
	.out(timer_cmd)
);

`define TEST_OUTPUT 1
`ifdef TEST_OUTPUT

reg timer_operate = 0;
always @(posedge clk)
	timer_operate = (timer_operate | timer_cmd[0]) & ~timer_cmd[1];

wire	[47:0] sample;
wire    sample_rdy;
apdtimer_all apdtimer(
	.clk(clk),
	.detectors(detectors),
	.pulseseq_outputs(laser_en),
	.operate(timer_operate),
	.reset_counter(timer_cmd[2]),

	.data_rdy(sample_rdy),
	.data(sample[46:0])
);


wire	[7:0] seqop_cmd;
strobe_bits_controller pulse_seq_operate_controller(
	.clk(clk),
	.mask_bit(cmd_rdy[1]),
	.data(cmd),
	.data_ack(cmd_ack[1]),
	.out(seqop_cmd)
);

reg pulse_seq_operate = 0;
always @(posedge clk)
	pulse_seq_operate = (pulse_seq_operate | seqop_cmd[0]) & ~seqop_cmd[1];

cntrl_pulse_sequencer pulseseq0(
	.clk(clk),
	.operate(pulse_seq_operate),
	.mask_bit(cmd_rdy[2]),
	.cmd(cmd),
	.cmd_ack(cmd_ack[2]),
	.out(laser_en[0])
);
cntrl_pulse_sequencer pulseseq1(
	.clk(clk),
	.operate(pulse_seq_operate),
	.mask_bit(cmd_rdy[3]),
	.cmd(cmd),
	.cmd_ack(cmd_ack[3]),
	.out(laser_en[1])
);
cntrl_pulse_sequencer pulseseq2(
	.clk(clk),
	.operate(pulse_seq_operate),
	.mask_bit(cmd_rdy[4]),
	.cmd(cmd),
	.cmd_ack(cmd_ack[4]),
	.out(laser_en[2])
);
cntrl_pulse_sequencer pulseseq3(
	.clk(clk),
	.operate(pulse_seq_operate),
	.mask_bit(cmd_rdy[5]),
	.cmd(cmd),
	.cmd_ack(cmd_ack[5]),
	.out(laser_en[3])
);

`else

reg [31:0] count;
initial count = 0;
always @(posedge clk)
begin
	if (count == 0)
		count <= 32'd480000;
	else
		count <= count - 1;
end

assign sample_rdy = (count == 0);
assign sample = 48'hfeeddeadbeed;
//assign cmd_ack = 1'b1;

`endif

//////////////////////////////
// Sample FIFO


wire samp_buf_full;
wire samp_buf_rdnext;
wire samp_buf_empty;
wire [47:0] samp_buf_out;

reg samp_lost;
initial samp_lost = 0;
assign sample[47] = samp_lost;

// Track dropped samples
always @(posedge clk)
begin
	if (sample_rdy && samp_buf_full)
		samp_lost <= 1;
	else if (sample_rdy && ~samp_buf_full)
		samp_lost <= 0;
end

sample_fifo samp_buf(
	.wrclk(clk),
	.wrreq(sample_rdy & ~samp_buf_full),
	.wrfull(samp_buf_full),
	.data(sample),

	.rdclk(fx2_clk),
	.rdreq(samp_buf_rdnext),
	.rdempty(samp_buf_empty),
	.q(samp_buf_out)
);


sample_multiplexer multiplexer(
	.clk(fx2_clk),
	.sample_rdy(~samp_buf_empty),
	.sample(samp_buf_out),
	.sample_ack(samp_buf_rdnext),

	.data_rdy(data_rdy),
	.data(data),
	.data_ack(data_ack)
);

/*
summator sample_counter(
	.clk(clk),
	.increment(sample_rdy & ~samp_buf_full),
	.readout_clr(request_length),
	.sum_out(length)
);
*/

endmodule

