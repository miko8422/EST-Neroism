# EST Tools — Local Setup Guide (Neroism)

Personal setup reference for deploying the Enzyme Function Initiative (EFI) EST tools on a local machine. This covers everything from dependency installation through running the GenerateSSN pipeline.

For full upstream documentation see `docs/getting_started.rst` and the `docs/source/` tree.

---

## Prerequisites

Ensure these are available on your system before starting:

| Requirement | Version | Notes |
|---|---|---|
| OS | Linux or POSIX | macOS works; Windows requires WSL |
| Java | 17+ | Required by Nextflow |
| Python | 3.10+ | For parameter scripts and pyEFI |
| Git | any | For cloning the repo |

---

## Environment Variables

All external tools live under a single `$EFIDEPS` directory. Set this once and add its `bin/` to your PATH:

```bash
export EFIDEPS=/path/to/your/deps   # e.g. ~/efi-deps
export PATH=$EFIDEPS/bin:$PATH
```

Add both lines to your `~/.zshrc` or `~/.bashrc` so they persist across sessions.

---

## Step 1: Install Dependencies

### 1.1 Nextflow — v24.04.4 (exact version required)

> **Important:** Only version 24.04.4 is supported. Do not use a newer release.

```bash
wget https://github.com/nextflow-io/nextflow/releases/download/v24.04.4/nextflow-24.04.4-all
chmod +x nextflow-24.04.4-all
mv nextflow-24.04.4-all $EFIDEPS/bin/nextflow
```

Verify:
```bash
nextflow -version
# Should report: nextflow version 24.04.4
```

### 1.2 DuckDB — v1.0.0

```bash
wget https://github.com/duckdb/duckdb/releases/download/v1.0.0/duckdb_cli-linux-amd64.zip
unzip duckdb_cli-linux-amd64.zip
mv duckdb $EFIDEPS/bin/duckdb
chmod +x $EFIDEPS/bin/duckdb
```

### 1.3 BLAST — legacy v2.2.26 (not BLAST+)

> **Important:** The pipeline requires the **legacy** BLAST v2.2.26, not modern BLAST+.

```bash
wget https://ftp.ncbi.nlm.nih.gov/blast/executables/legacy.NOTSUPPORTED/2.2.26/blast-2.2.26-x64-linux.tar.gz
tar -xzf blast-2.2.26-x64-linux.tar.gz -C $EFIDEPS/
ln -s $EFIDEPS/blast-2.2.26/bin/blastall $EFIDEPS/bin/blastall
```

### 1.4 CD-HIT — v4.8.1

```bash
wget https://github.com/weizhongli/cdhit/releases/download/V4.8.1/cd-hit-v4.8.1-2019-0228.tar.gz
tar -xzf cd-hit-v4.8.1-2019-0228.tar.gz -C $EFIDEPS/
cd $EFIDEPS/cd-hit-v4.8.1-2019-0228
make
mv cd-hit $EFIDEPS/bin/cd-hit
```

---

## Step 2: Python Environment

From the repo root:

```bash
python -m venv efi-env
source efi-env/bin/activate
pip install -r requirements.txt
```

If `pyEFI` fails to install from `requirements.txt`, install it directly:

```bash
pip install lib/pyEFI
```

---

## Step 3: Perl Environment

### 3.1 Set the Perl install path

```bash
export PERL5INSTALL=$EFIDEPS/perl5
mkdir -p $PERL5INSTALL
```

### 3.2 Install cpanminus and local::lib

```bash
wget -O- http://cpanmin.us | perl - -l $PERL5INSTALL App::cpanminus local::lib
```

### 3.3 Generate the Perl environment file

Run this from the repo root:

```bash
perl -I $PERL5INSTALL/lib/perl5 -Mlocal::lib=$PERL5INSTALL > perl_env.sh
source perl_env.sh
```

### 3.4 Install Perl dependencies

```bash
cpanm --installdeps .
```

If `XML::LibXML` fails (needs `libxml2` dev headers), force it through:

```bash
cpanm --force --installdeps .
```

Verify XML::LibXML installed:
```bash
perl -MXML::LibXML
# Should hang waiting for input (Ctrl+C to exit) — no error means success
```

---

## Step 4: Test Data and Tests

### 4.1 Download the small test dataset

```bash
bash tests/download_example.sh
```

Default location after download:
```
tests/test_data/sqlite/
├── blastdb/
├── efi.config
└── efi_db.sqlite
```

### 4.2 Set up the test environment

Basic setup using default test data directory:
```bash
source tests/test_env.sh
```

With a custom directory or options:
```bash
source tests/test_env.sh --data-dir /path/to/test_data
source tests/test_env.sh --data-dir /path/to/test_data --results-dir /path/to/results
```

Key `test_env.sh` flags:

| Flag | Default | Description |
|---|---|---|
| `--data-dir` | `tests/test_data/sqlite` | Path to test dataset |
| `--results-dir` | auto | Where test output goes |
| `--db-type` | `sqlite` | `sqlite` or `mysql` |
| `--db-name` | auto | Override the database file/name |
| `--fasta-db` | auto | Path to BLAST DB (use DB name, not file) |
| `--config-file` | auto | Path to `efi.config` |

### 4.3 Run all tests

```bash
# Docker
bash tests/runtests.sh docker.config

# Singularity
bash tests/runtests.sh singularity.config
```

### 4.4 Run a single test module

After sourcing `test_env.sh`:
```bash
bash tests/modules/01_est_sequence_blast.sh $EFI_TEST_RESULTS_DIR docker.config
```

Test scripts are in `tests/modules/` with numeric prefixes (`01_`, `02_`, etc.).

---

## Step 5: Database Setup (Reference — Do Not Download During Testing)

> **WARNING:** The full EFI database set is approximately 1 TB uncompressed (~460 GB compressed). Do **not** run the download script during local testing.

### What is required for full production runs

| Database | Size (compressed) | Purpose |
|---|---|---|
| SQLite metadata DB | ~80 GB | Protein families, taxonomy, UniRef |
| BLAST sequence DB | ~185 GB | BLAST sequence retrieval |
| DIAMOND sequence DB | ~185 GB | DIAMOND/CGFP analysis |

### Expected directory layout (when ready)

```
/data/efi/
├── efi_202408.sqlite      # Metadata database
├── efi.config             # Config file pointing to SQLite
├── blastdb/               # BLAST databases (6 variants)
│   ├── combined.fasta.*
│   ├── uniref90.fasta.*
│   └── ...
└── diamonddb/             # DIAMOND database
    └── combined.fasta.dmnd
```

### efi.config for SQLite

```ini
[database]
dbi=sqlite
```

### Download script (for future use)

```
# Reference only — do not run during testing:
# bash scripts/download_efi_dbs.sh \
#     --data-dir /data/efi \
#     --source-url https://efi.igb.illinois.edu/downloads/databases/latest/
```

For details see `docs/source/guides/databases.rst`.

---

## Step 6: Running the GenerateSSN Pipeline

The typical flow is: **EST pipeline first → GenerateSSN pipeline second**.

### 6.1 Activate environments (every new session)

```bash
source efi-env/bin/activate
source perl_env.sh
```

### 6.2 Run the EST pipeline (example: family mode)

```bash
results_dir="/data/results/my_family_run"

python bin/create_est_nextflow_params.py family \
    --families PF07476 \
    --output-dir $results_dir \
    --efi-config /data/efi/efi.config \
    --efi-db /data/efi/efi_202408.sqlite \
    --nextflow-config conf/est/docker.config

bash $results_dir/run_nextflow.sh
```

Use `conf/est/singularity.config` if running with Singularity instead of Docker.

### 6.3 Generate SSN from EST output (auto mode — recommended)

```bash
python bin/create_generatessn_nextflow_params.py auto \
    --filter-min-val 23 \
    --ssn-name ssn.xgmml \
    --ssn-title "My SSN Title" \
    --est-output-dir $results_dir \
    --efi-config /data/efi/efi.config \
    --efi-db /data/efi/efi_202408.sqlite \
    --nextflow-config conf/generatessn/docker.config

bash $results_dir/ssn/run_nextflow.sh
```

### 6.4 GenerateSSN (manual mode)

Use this if you have pre-existing BLAST/FASTA/metadata files rather than EST pipeline output:

```bash
python bin/create_generatessn_nextflow_params.py manual \
    --blast-parquet /path/to/1.out.parquet \
    --fasta-file /path/to/sequences.fasta \
    --seq-meta-file /path/to/metadata.file \
    --filter-min-val 23 \
    --ssn-name ssn.xgmml \
    --ssn-title "My SSN Title" \
    --nextflow-config conf/generatessn/docker.config

bash output_dir/run_nextflow.sh
```

### 6.5 Key GenerateSSN arguments

| Argument | Required | Description |
|---|---|---|
| `--filter-min-val` | Yes | Alignment score threshold (BLAST results where score >= value are kept) |
| `--ssn-name` | Yes | Output filename, e.g. `ssn.xgmml` |
| `--ssn-title` | Yes | Descriptive label embedded in the SSN |
| `--filter-parameter` | No | What to filter on; default `alignment_score` (do not change unless expert) |
| `--min-length` | No | Exclude sequences shorter than N |
| `--max-length` | No | Exclude sequences longer than N (default: 50000) |
| `--uniref-version` | No | `90` or `50` — for UniRef annotation in manual mode |

### 6.6 SLURM submission (if applicable)

```bash
python bin/create_nextflow_job.py generatessn auto \
    --filter-min-val 23 \
    --ssn-name ssn.xgmml \
    --ssn-title "My SSN Title" \
    --est-output-dir $results_dir \
    --efi-config /data/efi/efi.config \
    --efi-db /data/efi/efi_202408.sqlite \
    --nextflow-config conf/generatessn/slurm.config

sbatch run_nextflow.sh
```

---

## Session Activation Checklist

Every new terminal session before running any pipeline:

```bash
export EFIDEPS=/path/to/your/deps
export PATH=$EFIDEPS/bin:$PATH
export PERL5INSTALL=$EFIDEPS/perl5

source /path/to/EST-Neroism/efi-env/bin/activate
source /path/to/EST-Neroism/perl_env.sh
```

> If you added `EFIDEPS` and `PATH` to your shell profile, only the last two `source` lines are needed.

---

## Quick Reference: Key Files

| File | Purpose |
|---|---|
| `conf/est/docker.config` | Nextflow config for EST pipeline (Docker) |
| `conf/est/singularity.config` | Nextflow config for EST pipeline (Singularity) |
| `conf/generatessn/docker.config` | Nextflow config for GenerateSSN (Docker) |
| `bin/create_est_nextflow_params.py` | Generates EST run parameters and script |
| `bin/create_generatessn_nextflow_params.py` | Generates GenerateSSN parameters and script |
| `bin/create_nextflow_job.py` | Generates SLURM job scripts |
| `tests/download_example.sh` | Downloads small test dataset |
| `tests/test_env.sh` | Sets test environment variables |
| `tests/runtests.sh` | Runs full test suite |
| `scripts/download_efi_dbs.sh` | Downloads full production databases (do not run during testing) |
| `efi.config.example` | Example EFI config file |
