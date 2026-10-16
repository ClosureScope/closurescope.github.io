#import "../../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs: Low-Rank Attention",
)

Low-rank attention reduces the number of keys and values against which queries interact. This decreases the *sequence dimension* of $K$ and $V$.

= Linformer

Ordinary attention forms an $n times n$ attention score matrix. Linformer starts from the hypothesis that the effective attention map can be represented with a much smaller rank $r$.

Linformer learns projections along the sequence axis to compress information:

$
  E,F in RR^(r times n), quad r << n
$
and define

$
  K^prime = E K, quad V^prime = F V
$

Then $K^prime in RR^(r times d)$ and $V^prime in RR^(r times d)$.

The resulting operation is

$
  Y = "softmax" ((Q K^(prime T)) / sqrt(d)) V^prime
$

The score matrix now has shape $n times r$. The complexity is reduced to $O(n r d)$ from $O(n^2 d)$.

The learned $E$ and $F$ may be shared across heads or layers.

*Remark:* Linformer exploits low effective rank in token interactions. However, sequence-length reduction loses information. Projecting $K$ and $V$ along the sequence dimension can mix future tokens into past representations, preventing straightforward application of causal masking. Its fixed-length projections also limit straightforward streaming to arbitrary sequence lengths.


= FLuRKA

Low-rank attention compresses tokens, while kernel-based attention factorizes a similarity kernel. FLuRKA combines the advantages of both methods.

As in Linformer, let

$
  K^prime = E K, quad V^prime = F V
$

where $E,F in RR^(r times n)$ and $r << n$.

As in kernel-based attention, let $phi: RR^d -> RR^m$
$
  kappa(q, k) approx phi(q)^T phi(k)
$



$
  Y = D^(-1) phi(Q) (phi(K^prime)^T V^prime)
$


$
  D = "diag"(phi(Q) (phi(K^prime)^T bold(1)))
$

With $phi(Q) in RR^(n times m), phi(K^prime) in RR^(r times m), V^' in RR^(r times d)$

The complexity is $O(n r d + n m d).$

*Remark:* FLuRKA combines *sequence compression* and *kernel factorization*.


= Luna

Luna replaces full self-attention with two attention operations: *pack* and *unpack*. Instead of using a fixed sequence projection as in Linformer, it uses a short auxiliary sequence $P in RR^(r times d)$ where $r << n$ as the query to summarize the input.

*Pack*
$
  Q_"pack" = P W_"pack"^Q,
  quad K_"pack" = X W_"pack"^K,
  quad V_"pack" = X W_"pack"^V
$

$
  Z = "softmax" (
    (Q_"pack" K_"pack"^T) / sqrt(d)
  ) V_"pack"
$

Note that $Q_"pack" in RR^(r times d), K_"pack" in RR^(n times d), V_"pack" in RR^(n times d)$, and $Z in RR^(r times d)$.
The complexity of *Pack* is $O(n r d)$. Packing uses $P$ as a query to compress the information of $X$ into $Z$.

*Unpack*
$
  Q_"unpack" = X W_"unpack"^Q,
  quad K_"unpack" = Z W_"unpack"^K,
  quad V_"unpack" = Z W_"unpack"^V
$

$
  Y = "softmax" (
    (Q_"unpack" K_"unpack"^T) / sqrt(d)
  ) V_"unpack"
$


Note that $Q_"unpack" in RR^(n times d), K_"unpack" in RR^(r times d), V_"unpack" in RR^(r times d)$. The complexity of *Unpack* is $O(n r d)$. Unpacking uses the original query $Q_"unpack"$ to interact with the compressed $K_"unpack"$ and $V_"unpack"$.

*Remark:* Luna first packs $X$ into $Z$ through a short auxiliary sequence $P$, and then uses the original sequence as queries to retrieve contextual information from the packed keys and values.
