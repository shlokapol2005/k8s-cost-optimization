# Screenshots — Kubernetes Cost Optimization

Screenshots captured from Grafana and OpenCost during the baseline and optimized phases.

## Files

| File | Description |
|------|-------------|
| `baseline-grafana-cpu.png` | Grafana CPU dashboard — baseline phase. Shows 3500m total requests vs ~84m actual usage. Large gap visible between requested and actual CPU. |
| `baseline-grafana-memory.png` | Grafana memory dashboard — baseline phase. Shows ~3.5Gi total requests vs ~24Mi actual. Memory efficiency ~1%. |
| `baseline-opencost-allocation.png` | OpenCost Allocations tab — cost-demo namespace, baseline. Total cost: **$0.119490/hr**. Efficiency: 3.5%. |
| `optimized-grafana-cpu.png` | Grafana CPU dashboard — optimized phase. Total CPU requests dropped to 120m. Requests and actual usage are now close together. |
| `optimized-grafana-memory.png` | Grafana memory dashboard — optimized phase. Total memory requests 72Mi, closely matching actual usage. |
| `optimized-opencost-allocation.png` | OpenCost Allocations tab — cost-demo namespace, optimized. Total cost: **$0.000580/hr** (↓ 99.5%). Efficiency: 8.7%. |
| `before-after-comparison.png` | Side-by-side summary dashboard showing all key metrics before and after optimization. |

## Key Results Visible in Screenshots

- **CPU requests**: 3500m → 120m (↓ 96.6%)
- **Memory requests**: ~3.5Gi → 72Mi (↓ 98%)
- **Estimated cost**: $0.1195/hr → $0.0006/hr (↓ 99.5%)
- **Cluster efficiency**: 3.5% → 8.7%
- **Annualised saving**: ~$1,041.85/year (cost-demo namespace only)

> Pricing model: approximate AWS us-east-1 t3.medium on-demand rates via OpenCost.
> These are estimated resource allocation costs, not actual cloud bills.
