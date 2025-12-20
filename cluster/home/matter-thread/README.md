# OpenThread Border Router (OTBR) Deployment

This deployment runs OpenThread Border Router using the second chip (CC2674P10) on the SLZB-MR3 device.

## Configuration

- **Device**: SLZB-MR3 at `10.0.5.11:7638`
- **Protocol**: Spinel over TCP (Thread/Matter)
- **Web UI**: Accessible via `https://matter.kng.house` (requires Authentik auth)
- **Container**: `openthread/otbr:latest`

## Features

- Thread Border Router functionality
- Matter device commissioning
- IPv6 routing between Thread network and infrastructure
- NAT64 for IPv4 connectivity
- DNS64 for DNS resolution
- mDNS service discovery

## Web Interface

Access the OTBR web interface at `https://matter.kng.house` to:
- Form/join Thread networks
- Commission Matter devices
- View network topology
- Monitor connected devices
- Run diagnostics

## Backup

Daily backups run at 3:30 AM, keeping the last 30 backups in the `matter-thread-backups` PVC.

## Authentik Setup

See [Authentik Configuration Guide](./docs/AUTHENTIK-SETUP.md) for setting up the authentication provider.

## Troubleshooting

```bash
# Check pod status
kubectl get pod -n matter-thread

# View logs
kubectl logs -n matter-thread deployment/otbr

# Check service
kubectl get svc -n matter-thread otbr

# Test TCP connection to SLZB-MR3
nc -zv 10.0.5.11 7638
```

## References

- [OpenThread.io Documentation](https://openthread.io/)
- [OTBR Docker Guide](https://openthread.io/guides/border-router/docker)
- [Matter Specification](https://csa-iot.org/all-solutions/matter/)
