#!/bin/bash

# ArgoCD Installation Automation Script
set -e

echo "🚀 Starting ArgoCD Installation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if StatefulSet is ready
check_statefulset_ready() {
    local name=$1
    local namespace=$2
    local ready=$(kubectl get statefulset $name -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get statefulset $name -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if Deployment is ready
check_deployment_ready() {
    local name=$1
    local namespace=$2
    local ready=$(kubectl get deployment $name -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment $name -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to wait for resources with better logic
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $resource_type: $resource_name"
    
    while [ $attempt -le $max_attempts ]; do
        if [[ "$resource_type" == "statefulset" ]]; then
            if check_statefulset_ready $resource_name $namespace; then
                print_success "$resource_type/$resource_name is ready!"
                return 0
            fi
        elif [[ "$resource_type" == "deployment" ]]; then
            if check_deployment_ready $resource_name $namespace; then
                print_success "$resource_type/$resource_name is ready!"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    print_error "Timeout waiting for $resource_type/$resource_name"
    return 1
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_status "Connected to cluster: $(kubectl config current-context)"

# Create argocd namespace
print_status "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
print_status "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD resources to be ready
print_status "Waiting for ArgoCD resources to be ready..."
print_warning "This may take a few minutes..."

# Give resources time to be created
sleep 10

# Show initial status
print_status "Checking initial resource status..."
echo "StatefulSets:"
kubectl get statefulsets -n argocd 2>/dev/null || echo "No StatefulSets found yet"
echo "Deployments:"
kubectl get deployments -n argocd 2>/dev/null || echo "No Deployments found yet"

# Wait for the StatefulSet (argocd-application-controller)
wait_for_resource "statefulset" "argocd-application-controller" "argocd"

# Wait for Deployments
deployments=("argocd-applicationset-controller" "argocd-dex-server" "argocd-notifications-controller" "argocd-redis" "argocd-repo-server" "argocd-server")

for deployment in "${deployments[@]}"; do
    wait_for_resource "deployment" "$deployment" "argocd"
done

# Final status check
print_status "Final resource status:"
echo ""
echo "StatefulSets:"
kubectl get statefulsets -n argocd
echo ""
echo "Deployments:"
kubectl get deployments -n argocd
echo ""
echo "Pods:"
kubectl get pods -n argocd

print_success "All ArgoCD resources are ready!"

# Get initial admin password
print_status "Retrieving ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Display connection information
echo ""
echo "==============================================="
print_success "ArgoCD Installation Complete!"
echo "==============================================="
echo ""
echo -e "${BLUE}ArgoCD Credentials:${NC}"
echo -e "Username: ${GREEN}admin${NC}"
echo -e "Password: ${GREEN}$ARGOCD_PASSWORD${NC}"
echo ""

# Ask user if they want to start port-forward
echo -e "${BLUE}Do you want to start port-forward to access ArgoCD UI? (y/n):${NC}"
read -r start_portforward

if [[ $start_portforward =~ ^[Yy]$ ]]; then
    print_status "Starting port-forward to ArgoCD server..."
    print_warning "Port-forward will run in the background. Use Ctrl+C to stop."
    echo ""
    echo "==============================================="
    print_success "ArgoCD UI Access Information"
    echo "==============================================="
    echo -e "${GREEN}✅ URL: https://localhost:8080${NC}"
    echo -e "${GREEN}✅ Username: admin${NC}"
    echo -e "${GREEN}✅ Password: $ARGOCD_PASSWORD${NC}"
    echo ""
    print_warning "Note: You may see a certificate warning in the browser - click 'Advanced' and 'Proceed' as it's normal for local development."
    echo ""
    print_status "Starting port-forward..."
    kubectl port-forward svc/argocd-server -n argocd 8080:443
else
    echo ""
    echo "==============================================="
    print_success "Manual Access Instructions"
    echo "==============================================="
    echo "1. Start port-forward:"
    echo -e "   ${YELLOW}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
    echo ""
    echo "2. Open in browser:"
    echo -e "   ${YELLOW}https://localhost:8080${NC}"
    echo ""
    echo "3. Login with:"
    echo -e "   Username: ${GREEN}admin${NC}"
    echo -e "   Password: ${GREEN}$ARGOCD_PASSWORD${NC}"
    echo ""
    echo "4. Or use ArgoCD CLI:"
    echo -e "   ${YELLOW}argocd login localhost:8080${NC}"
    echo ""
    print_warning "Note: You may see a certificate warning in the browser - this is normal for local development."
fi

echo ""
print_success "🎉 ArgoCD is ready to use!" 