#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-streaming-eks-cluster}"
NAMESPACE="streaming"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-}"

echo "=== Setting up CloudWatch Monitoring ==="
echo "Region  : ${AWS_REGION}"
echo "Cluster : ${CLUSTER_NAME}"

# Create Log Groups
echo "-> Creating log groups..."
for GROUP in \
  "/aws/eks/${CLUSTER_NAME}/application" \
  "/streaming-app/helloservice" \
  "/streaming-app/profileservice"; do
  aws logs create-log-group \
    --log-group-name "${GROUP}" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  Already exists: ${GROUP}"
  aws logs put-retention-policy \
    --log-group-name "${GROUP}" \
    --retention-in-days 30 \
    --region "${AWS_REGION}"
done

# Create Alarms
echo "-> Creating CloudWatch alarms..."

# CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "streaming-backend-high-cpu" \
  --alarm-description "Backend CPU > 80% for 5 minutes" \
  --metric-name pod_cpu_utilization \
  --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
               Name=Namespace,Value="${NAMESPACE}" \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --region "${AWS_REGION}" || true

# Memory alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "streaming-backend-high-memory" \
  --alarm-description "Backend memory > 85% for 5 minutes" \
  --metric-name pod_memory_utilization \
  --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
               Name=Namespace,Value="${NAMESPACE}" \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --region "${AWS_REGION}" || true

# 5xx errors alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "streaming-frontend-5xx-errors" \
  --alarm-description "5xx errors > 10 in 5 minutes" \
  --metric-name 5xxErrorCount \
  --namespace StreamingApp/Frontend \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --region "${AWS_REGION}" || true

# Node health alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "streaming-eks-node-not-ready" \
  --alarm-description "EKS node not ready" \
  --metric-name cluster_node_count \
  --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
  --statistic Minimum \
  --period 60 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --region "${AWS_REGION}" || true

echo ""
echo "✅ CloudWatch setup complete!"
echo "   Log groups and 4 alarms created."
echo ""
echo "Verify with:"
echo "  aws cloudwatch describe-alarms --region ${AWS_REGION} --query 'MetricAlarms[*].AlarmName' --output table"
