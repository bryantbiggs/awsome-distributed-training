#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=4 # number of nodes to use
#SBATCH --job-name=mistral_8x7b-FSDP # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=8 # 4 for G5.12x, 8 for P4/P5

###############################
###### Container Variable #####
###############################
# Uncomment if you want to use a container instea of Virtual Environment.
#export CONTAINER_IMAGE=$(pwd)/pytorch-fsdp.sqsh
export DATA_PATH=/fsx
export FSX_MOUNT=$(pwd):$DATA_PATH

###########################
## Environment Variables ##
###########################

## Plenty of EFA level variables
## For G4dn and other G5, comment out all
#export FI_LOG_LEVEL=warn
export NCCL_DEBUG=INFO
export FI_PROVIDER=efa
export FI_EFA_USE_HUGE_PAGE=0    # Set to 0 when you see os.fork() causes OSError: Cannot allocate memory.  Disabling huge page causes minor performance hit.
## Switching SYNC_MEMOPS to zero can boost throughput with FSDP
## Disables CU_POINTER_ATTRIBUTE_SYNC_MEMOPS
## Reduces memory synchronizations
## https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__UNIFIED.html
export FI_EFA_SET_CUDA_SYNC_MEMOPS=0
# LD_PRELOAD is required for PyTorch to find the NCCL library
# This path assumes you are using the Deep Learning AMI
# If you are not using the DLAMI, you may need to update this path
export LD_PRELOAD=/usr/local/cuda-12.8/lib/libnccl.so
export NCCL_SOCKET_IFNAME=^docker,lo,veth,eth

## Set HuggingFace metadata timeout (in seconds) for large clusters
export HF_HUB_ETAG_TIMEOUT=60


########################
####### Container ######
########################

if [ ! -z $CONTAINER_IMAGE ];
then
    export TRAIN_SCRIPT=./train.py
    
    declare -a ARGS=(
        --container-image $CONTAINER_IMAGE
        --container-mounts $FSX_MOUNT
    )
fi

###########################
####### Torch Dist  #######
###########################

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
)

export TORCHRUN=torchrun
export TRAIN_SCRIPT=${TRAIN_SCRIPT:=../src/train.py}

############################
# mistral_8x7b Training Params ##
############################

declare -a TRAINING_ARGS=(
    --train_batch_size=4
    --val_batch_size=4
    --max_steps=200
    --seed=42
    --bf16=1
    --grad_clip=1.0
    --weight_decay=0.2
    --beta1=0.9
    --beta2=0.95
    --activation_checkpointing=1
    --intermediate_size=14336
    --num_key_value_heads=8
    --logging_freq=1
    --max_context_width=32768
    --vocab_size=32000
    --hidden_width=4096
    --num_layers=32
    --num_heads=32
    --resid_pdrop=0.1
    --embd_pdrop=0.1
    --attn_pdrop=0.1
    --summary_first_pdrop=0.1
    --initializer_range=0.02
    --model_type=mixtral
    --rotary_pct=0.25
    --rotary_emb_base=10000
    --lr=0.0001
    --lr_decay_style=cosine
    --min_lr=1e-5
    --warmup=0.0032
    --plateau=0.0
    --dataset=allenai/c4
    --tokenizer=mistralai/Mixtral-8x7B-v0.1
    --epochs=3
    --dataset_config_name=en
    --limit_all_gathers=1
    --sharding_strategy=full  # https://pytorch.org/docs/stable/fsdp.html
    --offload_activations=1
)

AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi
srun ${AUTO_RESUME} -l "${ARGS[@]}" ${TORCHRUN} "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${TRAINING_ARGS[@]}"