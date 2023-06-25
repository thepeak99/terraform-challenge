#!/bin/bash

eval "$(jq -r '@sh "QUEUE=\(.queue) REGION=\(.region)"')"

while true; do 
  message=$(aws --region $REGION sqs receive-message --queue-url $QUEUE --max-number-of-messages 1 --wait-time 20) 
  if [[ ! -z "$message" ]]; then
    break
  fi
done

receipt_handle=$(echo $message | jq -r .Messages[0].ReceiptHandle)
aws --region $REGION sqs delete-message --queue-url "$QUEUE" --receipt-handle "$receipt_handle"

echo $message | jq '{body: .Messages[0].Body}'
