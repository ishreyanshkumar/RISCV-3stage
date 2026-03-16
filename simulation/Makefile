# --- Variables ---
INC_DIR  = ../modules
BFLAGS   = -i $(INC_DIR) -f filelist.txt
TOP_MOD  = tb_pipeline
SNAPSHOT = riscv_sim
MEM_GEN  = ../mem_generator

# Vivado Tools
export PATH := C:/AMDDesignTools/2025.2/Vivado/bin:$(PATH)
XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: help clean sort addition negative fib xor

help:
	@echo "Usage: make <program_name> (e.g. make addition)"

# Generic Rule for all programs
sort addition negative fib xor:
	# 1. Generate Hex Files
	$(MAKE) clean -C $(MEM_GEN)
	$(MAKE) $@ -C $(MEM_GEN)
	
	# 2. Vivado Simulation Flow
	$(XVLOG) $(BFLAGS)
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	
	# 3. Run Simulation (log to stdout to see $display)
	$(XSIM) $(SNAPSHOT) -tclbatch xsim_cfg.tcl -log stdout

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f pipeline.vcd
	@rm -f *.backup
	@rm -f simulation_results*.txt
	@rm -f *.log
	@rm -f *.jou
	@rm -f *.str	
	@rm -f *.wdb
	@rm -f stdout


