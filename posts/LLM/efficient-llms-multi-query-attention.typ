#import "../../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs: Multi-Query Attention",
)


= Multi-Query Attention (MQA)

Each attention head uses its own query projection $W_Q$, while all heads share the same key and value projections $W_K$ and $W_V$, thus sharing the same $K$ and $V$.

*Remark:* Dramatically reduces autoregressive KV-cache size and memory traffic. Sharing all KV representations can reduce head diversity.

= Grouped-Query Attention (GQA)

Divide the heads into groups. Within each group, each attention head shares the same $K$ and $V$.

*Remark:* Provides a continuous trade-off between MHA and MQA, often retaining accuracy with much lower cache bandwidth. Full attention over a sequence is still quadratic.

= Multi-Token Attention (MTA)

Process attention-score matrix with a lightweight $3 times 3$ 2D convolution to capture information between adjacent tokens, followed by cross-head 1D convolution to integrate information across heads.

*Remark:* Captures adjacent-token and cross-head patterns with few extra parameters. Convolution adds operators and does not inherently remove quadratic attention complexity.
