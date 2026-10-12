#!/bin/bash
# Send a user update through API Gateway and check the user microservice
# processed it: the response comes back from the Lambda function, and the
# function logged the address mapped by the request template.
set -euo pipefail

STACK=CdkUserMicroserviceStack
FUNCTION=UserMicroserviceLambda
MAX_ATTEMPTS=${MAX_ATTEMPTS:-30}
ADDRESS="CI street $(date +%s)"

API_URL=$(lstk aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?starts_with(OutputKey, 'MicroserviceAPIEndpoint')].OutputValue | [0]" --output text)
echo "API: $API_URL"

START_MS=$(( $(date +%s) * 1000 ))

response=$(curl -s --fail-with-body -X POST "${API_URL%/}/user" \
  -H 'Content-Type: application/json' \
  -d "{\"UserId\": 12345, \"Address\": \"$ADDRESS\", \"City\": \"San Francisco\", \"State\": \"California\", \"ZipCode\": 94111, \"Country\": \"United States\"}")
echo "Response: $response"

if ! echo "$response" | jq -e '.statusCode == 200 and .body == "Processed"' > /dev/null; then
  echo "Test failed: unexpected response from the user microservice"
  exit 1
fi
echo "PASS: user microservice processed the request"

logged=""
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  logged=$(lstk aws logs filter-log-events --log-group-name "/aws/lambda/$FUNCTION" \
    --start-time "$START_MS" --query 'events[].message' --output text 2>/dev/null || true)
  if [[ "$logged" == *"$ADDRESS"* && "$logged" == *"United States"* ]]; then
    break
  fi
  sleep 2
done
if [[ "$logged" != *"$ADDRESS"* ]]; then
  echo "Test failed: $FUNCTION did not log the address from the request"
  exit 1
fi
echo "PASS: request template passed the user fields to the function"

echo "Test passed: request went through API Gateway to the user microservice"
