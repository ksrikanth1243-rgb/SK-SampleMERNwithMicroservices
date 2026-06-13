#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:?Set SLACK_WEBHOOK_URL env var}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FUNCTION_NAME="streaming-sns-to-slack"

echo "=== StreamingApp ChatOps Setup ==="

# Create SNS Topic
echo "-> Creating SNS topic..."
DEPLOY_TOPIC=$(aws sns create-topic \
  --name "streaming-deploy-notifications" \
  --region "${AWS_REGION}" \
  --query TopicArn --output text)
echo "   Topic ARN: ${DEPLOY_TOPIC}"

# Create Lambda function code
echo "-> Creating Lambda function..."
mkdir -p /tmp/lambda-pkg

cat > /tmp/lambda-pkg/index.js << 'LAMBDA'
const https = require('https');
const url   = require('url');

exports.handler = async (event) => {
  const record  = event.Records[0].Sns;
  const subject = record.Subject || 'StreamingApp Notification';
  const message = record.Message;

  const lower = subject.toLowerCase();
  const color = lower.includes('success') ? '#36a64f' :
                lower.includes('fail')    ? '#d00000' : '#439FE0';
  const icon  = lower.includes('success') ? ':white_check_mark:' :
                lower.includes('fail')    ? ':x:' : ':information_source:';

  const payload = JSON.stringify({
    attachments: [{
      color,
      title: icon + '  ' + subject,
      text:  message,
      footer: 'StreamingApp CI/CD',
      ts: Math.floor(Date.now() / 1000)
    }]
  });

  const { hostname, path } = url.parse(process.env.SLACK_WEBHOOK_URL);

  await new Promise((resolve, reject) => {
    const req = https.request(
      { hostname, path, method: 'POST',
        headers: { 'Content-Type': 'application/json',
                   'Content-Length': Buffer.byteLength(payload) } },
      (res) => { res.on('data', () => {}); res.on('end', resolve); }
    );
    req.on('error', reject);
    req.write(payload);
    req.end();
  });

  return { statusCode: 200 };
};
LAMBDA

cd /tmp/lambda-pkg && zip -r /tmp/sns-to-slack.zip index.js && cd -

# Create IAM Role
echo "-> Creating Lambda IAM role..."
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

ROLE_ARN=$(aws iam create-role \
  --role-name "streaming-lambda-sns-role" \
  --assume-role-policy-document "${TRUST}" \
  --query Role.Arn --output text 2>/dev/null || \
  aws iam get-role \
  --role-name "streaming-lambda-sns-role" \
  --query Role.Arn --output text)

aws iam attach-role-policy \
  --role-name "streaming-lambda-sns-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

echo "   Role ARN: ${ROLE_ARN}"
sleep 10

# Deploy Lambda
echo "-> Deploying Lambda..."
aws lambda create-function \
  --function-name "${FUNCTION_NAME}" \
  --runtime nodejs18.x \
  --role "${ROLE_ARN}" \
  --handler index.handler \
  --zip-file fileb:///tmp/sns-to-slack.zip \
  --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" \
  --timeout 10 \
  --region "${AWS_REGION}" 2>/dev/null || \
aws lambda update-function-code \
  --function-name "${FUNCTION_NAME}" \
  --zip-file fileb:///tmp/sns-to-slack.zip \
  --region "${AWS_REGION}"

LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

# Subscribe Lambda to SNS
echo "-> Subscribing Lambda to SNS..."
aws sns subscribe \
  --topic-arn "${DEPLOY_TOPIC}" \
  --protocol lambda \
  --notification-endpoint "${LAMBDA_ARN}" \
  --region "${AWS_REGION}" || true

aws lambda add-permission \
  --function-name "${FUNCTION_NAME}" \
  --statement-id  "sns-deploy-invoke" \
  --action        "lambda:InvokeFunction" \
  --principal     "sns.amazonaws.com" \
  --source-arn    "${DEPLOY_TOPIC}" \
  --region        "${AWS_REGION}" 2>/dev/null || true

echo ""
echo "✅ ChatOps setup complete!"
echo "   SNS Topic : ${DEPLOY_TOPIC}"
echo "   Lambda    : ${LAMBDA_ARN}"
echo ""
echo "Add this to your Jenkinsfile environment:"
echo "   SNS_TOPIC_ARN = '${DEPLOY_TOPIC}'"
