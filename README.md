# Synchronous FIFO – UVM-Based Functional Verification

## Overview

This project implements a reusable UVM-based verification environment for a synchronous FIFO (First-In, First-Out) using SystemVerilog.

The verification environment follows the Universal Verification Methodology (UVM), using a modular, object-oriented architecture to generate stimulus, monitor DUT activity, compare actual results against expected behavior, and collect functional coverage.

The project also integrates SystemVerilog Assertions (SVA) to verify protocol behavior, FIFO state transitions, reset functionality, and boundary conditions.

## FIFO Specifications

| Parameter | Value |
|---|---|
| FIFO Type | Synchronous FIFO |
| Data Width | 16 bits |
| FIFO Depth | 8 entries |
| Clock Domain | Single clock |
| Reset | Active-low asynchronous reset |
| Verification Language | SystemVerilog |
| Methodology | UVM |

## UVM Testbench Architecture

The verification environment consists of the following components:

| Component | Description |
|---|---|
| Sequence Item | Defines randomized FIFO transactions and observed signals |
| Sequence | Generates directed and constrained-random stimulus |
| Sequencer | Controls and delivers transactions to the driver |
| Driver | Drives transactions onto the FIFO interface |
| Monitor | Samples DUT inputs and outputs and publishes transactions |
| Agent | Groups the sequencer, driver, and monitor |
| Scoreboard | Compares DUT outputs against a queue-based reference model |
| Coverage Collector | Collects functional coverage and cross coverage |
| Environment | Integrates the agent, scoreboard, and coverage collector |
| Test | Configures and executes verification scenarios |

### Verification Flow

```text
              UVM TEST
                  |
             UVM SEQUENCE
                  |
              SEQUENCER
                  |
               DRIVER
                  |
             FIFO INTERFACE
                  |
              FIFO DUT
                  |
               MONITOR
                  |
           Analysis Port
             /       \
            /         \
      SCOREBOARD    COVERAGE
          |             |
     Reference      Functional
       Model         Coverage
```

## Verification Scenarios

The project includes dedicated tests and sequences covering different FIFO operating conditions.

| Test | Verification Objective |
|---|---|
| Write Only | FIFO filling and overflow detection |
| Read Only | FIFO draining and underflow detection |
| Write/Read | Simultaneous read and write operations |
| Flags | Full, empty, almost-full, and almost-empty flags |
| Wrap Around | Read/write pointer wrap-around and data integrity |
| Reset | Asynchronous reset under different FIFO states |
| Random | Constrained-random stimulus |
| Main | Complete verification regression |

### Constrained-Random Verification

Implemented randomized transaction generation using SystemVerilog constraints and distribution weights.

Randomized signals include:
- Reset
- Write enable
- Read enable
- Input data

Corner-case data patterns are also generated, including:
- All zeros
- All ones
- Alternating bit patterns
- Random data values

## Scoreboard & Reference Model

Developed a self-checking scoreboard using a SystemVerilog queue as a golden reference model.

The scoreboard checks:
- Output data correctness.
- Write acknowledgment.
- Overflow and underflow behavior.
- Full and empty flags.
- Almost-full and almost-empty flags.
- Correct FIFO occupancy and transaction ordering.

Any mismatch between the DUT and expected behavior is reported using UVM error messages.

## Assertion-Based Verification (SVA)

Implemented a dedicated SVA module bound to the FIFO DUT.

Assertions cover:
- Synchronous and asynchronous reset behavior.
- FIFO flag correctness.
- Write acknowledgment and overflow behavior.
- Occupancy counter updates.
- Simultaneous read/write operations.
- Read and write pointer boundaries.
- Pointer wrap-around.
- Data output stability.
- Illegal FIFO state combinations.

Cover properties are also used to track important sequential scenarios.

## Coverage Results

The project uses ModelSim coverage analysis to evaluate RTL and verification completeness.

### Code Coverage

| Coverage Metric | Result |
|---|---:|
| Statement Coverage | 100% |
| Branch Coverage | 100% |
| Condition Coverage | 100% |
| Toggle Coverage | 100% |
| Overall Code Coverage | 100% |

### Functional Coverage

| Metric | Result |
|---|---:|
| Covergroups | 5 |
| Coverpoints and Crosses | 33 |
| Coverage Bins | 170/170 |
| Functional Coverage | 100% |

### Assertion & Directive Coverage

| Metric | Result |
|---|---:|
| Assertions | 33/33 |
| Assertion Coverage | 100% |
| Cover Directives | 23/23 |
| Directive Coverage | 100% |

Detailed reports are available in the repository:
- `code_coverage.txt`
- `functional_coverage.txt`
- `sequential_domain_coverage.txt`

## Tools & Technologies

- SystemVerilog
- Universal Verification Methodology (UVM)
- ModelSim
- SystemVerilog Assertions (SVA)
- Constrained-Random Verification
- Functional Coverage
- Object-Oriented Programming
- Self-Checking Testbenches

## Running the Simulation

### Prerequisites

- ModelSim with UVM support.
- SystemVerilog simulation support.
- UVM library configured in the simulator.

### Execution

1. Clone the repository:

```bash
git clone https://github.com/Mai-Fakhry/FIFO_UVM_project.git
```

2. Navigate to the project directory:

```bash
cd FIFO_UVM_project
```

3. Open ModelSim and execute:

```tcl
do run.do
```

The simulation script:
- Creates the working library.
- Compiles the source files.
- Runs the `FIFO_main_test`.
- Enables code and functional coverage.
- Saves the coverage database.
- Generates code, functional, and assertion coverage reports.

## Repository Structure

```text
FIFO_UVM_project/
│
├── FIFO.sv
├── FIFO_INTERFACE.sv
├── FIFO_TOP.sv
├── FIFO_SVA.sv
│
├── FIFO_pkg.sv
├── FIFO_config.sv
│
├── FIFO_agent.sv
├── FIFO_driver.sv
├── FIFO_monitor.sv
├── FIFO_sequencer.sv
├── FIFO_seq_item.sv
├── FIFO_sequences.sv
├── FIFO_scoreboard.sv
├── FIFO_coverage.sv
├── FIFO_env.sv
├── FIFO_tests.sv
│
├── shared_pkg.sv
├── src_files.list
├── run.do
├── wave.do
│
├── code_coverage.txt
├── functional_coverage.txt
├── sequential_domain_coverage.txt
├── FIFO_cov.ucdb
│
├── FIFO_UVM.pdf
└── README.md
```

## Project Objectives

This project demonstrates practical experience in:

- Building reusable UVM verification environments.
- Developing constrained-random sequences.
- Implementing UVM agents and testbench components.
- Creating self-checking scoreboards and reference models.
- Writing SystemVerilog Assertions.
- Performing functional and code coverage analysis.
- Verifying FIFO corner cases and sequential behavior.

## Author

**Mai Fakhry**

Computer and AI Engineering  
Ain Shams University

[GitHub Repository](https://github.com/Mai-Fakhry/FIFO_UVM_project)
