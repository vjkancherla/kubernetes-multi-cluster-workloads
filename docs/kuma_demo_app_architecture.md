# Kuma Counter Demo Architecture

## Overview

The kuma-counter-demo showcases Kuma's multi-zone service mesh capabilities through a simple counter application with an asymmetric service distribution across two zones.

## Architecture Diagram
![Kuma Counter Demo](../images/kuma_demo_app_arch.png)


## Service Distribution

### Member-Cluster-1 (Zone-1)
- **Redis Service**: Centralized data store running on port 6379
- **Frontend Service**: Web application running on port 3000

### Member-Cluster-2 (Zone-2)  
- **Frontend Service**: Web application running on port 3000
- **No Redis Service**: Zone-2 relies on cross-zone access to Redis in Zone-1

## Traffic Flow

### Local Access (Zone-1)
Frontend services in Zone-1 connect directly to the local Redis instance, providing optimal performance with minimal latency.

### Cross-Zone Access (Zone-2)
Frontend services in Zone-2 access Redis through Kuma's multi-zone architecture:

1. **Service Request**: Frontend-2 makes a request to `redis_kuma-demo_svc_6379.mesh:80`
2. **Zone Egress**: Traffic is routed through Zone-2's egress proxy
3. **Cross-Zone Transit**: Request travels from Zone Egress-2 to Zone Ingress-1
4. **Zone Ingress**: Zone-1's ingress proxy receives the cross-zone traffic
5. **Service Delivery**: Request is forwarded to the Redis service in Zone-1 on port 6379

## Load Balancing

Users can access the frontend application through either zone:
- **Zone-1 Frontend**: Serves requests with local Redis access
- **Zone-2 Frontend**: Serves requests with cross-zone Redis access

Kuma automatically handles load balancing and service discovery, making the distributed architecture transparent to end users.

## Key Kuma Features Demonstrated

- **Multi-Zone Service Mesh**: Seamless connectivity across zones
- **Cross-Zone Service Discovery**: Automatic resolution of `redis_kuma-demo_svc_6379.mesh:80` DNS entries
- **Zone Egress/Ingress**: Secure and efficient cross-zone communication
- **Transparent Proxying**: Applications connect using standard service names
- **Port Mapping**: Kuma maps the .mesh:80 endpoint to the actual Redis port 6379
- **Automatic Load Balancing**: Traffic distribution across available service instances
- **mTLS Encryption**: All service-to-service communication is automatically encrypted

## Benefits

This architecture demonstrates how Kuma enables:
- **Geographic Distribution**: Services can be deployed across different regions or clusters
- **Resource Optimization**: Centralized stateful services (Redis) with distributed stateless services (Frontend)
- **High Availability**: Multiple frontend instances provide redundancy
- **Operational Simplicity**: Standard Kubernetes service discovery patterns work across zones