# RISC-V Three-Stage Pipelined Processor

This repository contains a Register-Transfer Level (RTL) implementation of a 32-bit RISC-V integer architecture (RV32I) pipelined processor, written in Verilog.

## 1. Architecture Overview

The core implements a classic 3-stage pipeline to achieve high throughput while maintaining simplicity:

1. **Instruction Fetch and Decode (IF_ID)**
   - Fetches instructions from the Instruction Memory (IMEM).
   - Decodes the fetched instruction.
   - Extracts immediate values and register addresses.
2. **Execute (EX)**
   - Computes standard arithmetic and logic unit (ALU) operations.
   - Resolves branch targets and conditions.
   - Computes memory addresses for load and store instructions.
3. **Writeback (WB)**
   - Interfaces with the Data Memory (DMEM).
   - Performs memory reads (LOAD) and memory writes (STORE).
   - Writes computed results or loaded data back to the register file.

## 2. Required Tools

Install the following before running the project:

* RISC-V GNU Toolchain
* Vivado (for simulation)
* Python
* Make

## 3. Toolchain Installation

### 3.1 Install Git Bash
Download and install Git:
[https://git-scm.com/download/win](https://git-scm.com/download/win)

Use default installation settings.

Open a terminal using:
**Right Click → Git Bash Here**

**All project commands** should be executed in **Git Bash**.

### 3.2 Install Node.js (npm)
Download and install **Node.js**, which includes **npm**:
[https://nodejs.org/en/download](https://nodejs.org/en/download)

Verify installation in the Git Bash:
```bash
node --version
npm --version
```

### 3.3 Install xPack RISC-V Toolchain
Install the RISC-V Embedded GCC toolchain using **npm**.

Install xpm:
```bash
npm install --global xpm
```

Install the RISC-V toolchain:
```bash
xpm install --global @xpack-dev-tools/riscv-none-elf-gcc
```

### 3.4 Add Toolchain to PATH
The toolchain will be installed at a location similar to:
`C:\Users\<username>\AppData\Roaming\xPacks\@xpack-dev-tools\riscv-none-elf-gcc\<version>\.content\bin`

Add this **bin directory** to the Windows **PATH**.

Steps:
1. Open **Environment Variables**
2. Edit **System Path**
3. Add the **toolchain bin directory**

### 3.5 Verify Installation
Run in Git Bash:
```bash
riscv-none-elf-gcc --version
```
If successful, the GCC version information will be displayed.

### 3.6 Install Make
If you have Chocolatey installed, run:
```bash
choco install make
```
Then verify in Git Bash:
```bash
make --version
```

## 4. Quick Start (After Installation)

Run:
```bash
cd RISCV_Three_Stage/simulation
make addition
```

This will automatically:
* Compile the C program
* Generate **instruction and data memory files**
* Launch **Vivado simulation**
* Produce **waveform output**

### Custom Testcases

Several testcases are supported out of the box:

*   `make addition`
*   `make negative`
*   `make xor`
*   `make fib`
*   `make sort`

You can add completely new custom testcases by creating a `code_[name].c` in `mem_generator/`, editing `mem_generator/Makefile` to set it as a target, and making a new `[name]` rule in `simulation/Makefile`.

### Simulation Output

Upon completing execution, you will see output in the terminal showing the Program Counter (`next_pc`) progressing alongside specific register write results (`time`, `result`). 

These final results are simultaneously written out locally:
1. **`simulation/simulation_results.txt`**: A clean log of exact timestamps, the active branches, and the changing result values of output variables.
2. **`simulation/pipeline.vcd`**: A full Value Change Dump (VCD) waveform file containing the timing toggles of all processor signals for deep debugging.
