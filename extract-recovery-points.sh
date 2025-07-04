#!/bin/bash

# Input: Lists of target EC2 instance IDs and volume IDS

TARGET_INSTANCES=("i-05320e9b76f93fd8e")
TARGET_VOLUMES=("vol-068c2489d06ae47ab")

# List of AMI IDs to skip
SKIP_AMIS=()

#Output File
OUTPUT_FILE="to_delete_recovery_points.txt"
> "$OUTPUT_FILE" # Clear previous output

#Get all backup vaults
VAULTS=$(aws backup list-backup-vaults --query 'BackupVaultList[*].BackupVaultName' --output text)

for VAULT in $VAULTS; do
    echo "Checking vault: $VAULT"

    RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
      --backup-vault-name "$VAULT" \
      --query 'RecoveryPoints[*].RecoveryPointArn' \
      --output text)
    
    for RP_ARN in $RECOVERY_POINTS; do
        echo "Inspecting recovery point: $RP_ARN"

        DETAILS= $(aws backup describe-recovery-point \
        --backup-vault-name "$VAULT" \
        --recovery-point-arn "$RP_ARN")

        RESOURCE_TYPE=$(echo "$DETAILS" | jq -r '.ResourceType')
        RESOURCE_ARN=$(echo "$DETAILS" | jq -r '.ResourceArn')
        RESOURCE_ID=$(basename "$RESOURCE_ARN")

        # Skip AMIs in skip list
        if [["$RESOURCE_TYPE" == "EC2"]]; then
            for AMI in "${SKIP_AMIS[@]}"; do
                if [["$RESOURCE_ID" == "$AMI"]]; then
                    echo "Skipping AMI: $RESOURCE_ID"
                    continue 2
                fi
            done
        fi

        # Check if resource ID is in our target list
        if [["$RESOURCE_TYPE" == "EC2"]]; then
            for ID in "${TARGET_INSTANCES[@]}"; do
                if [[ "$RESOURCE_ID" == "$ID"]]; then
                    echo "$VAULT,$RP_ARN" >> "$OUTPUT_FILE"
                    echo " Marked for deletion (EC2): $RESOURCE_ID"
                    break
                fi
            done
        elif [[ "$RESOURCE_TYPE" == "EBS"]]; then
            for ID in "${TARGET_VOLUMES[@]}"; do
                if [["$RESOURCE_ID" == "$ID"]]; then
                    echo "   ✅ Marked for deletion (EBS): $RESOURCE_ID"
                    break
                fi
            done
        fi
    done
done

echo "Extraction complete. Output saved to: $OUTPUT_FILE"
