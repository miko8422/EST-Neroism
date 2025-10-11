#!/bin/bash
#
# This is the default command-line interface template that is used for testing or by a user when
# running on a system through Docker or a manual installation.  Include here any environment setup
# that is required (e.g. source, venv) to run.

# Normally nothing should be changed here
nextflow -C /workspace/Workspace/EST/conf/est/docker.config -log /workspace/Workspace/EST/results/final_ssn/nextflow.log run /workspace/Workspace/EST/pipelines/est/est.nf -params-file /workspace/Workspace/EST/results/final_ssn/params.yml -with-report /workspace/Workspace/EST/results/final_ssn/report.html -with-timeline /workspace/Workspace/EST/results/final_ssn/timeline.html -w /workspace/Workspace/EST/results/final_ssn/work

