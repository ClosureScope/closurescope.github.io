#import "../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs: Kernel-Based Attention",
  date: "2026-10-13",
  category: "LLM",
)

Standard transformer attention is defined as

$ Y = "softmax"((Q K^T) / sqrt(d)) V $

Or in scalar form,

$ e_(i j) = (q_i^T k_j) / sqrt(d) $
$ alpha_(i j) = exp(e_(i j)) / (sum_(j) exp(e_(i j))) $
$ y_i = sum_j alpha_(i j) v_j $


The exponentiated logits can be interpreted as evaluations of an exponential dot-product kernel:

$
  kappa(q_i, k_j)
  = exp((q_i^T k_j) / sqrt(d))
$
$ alpha_(i j) = kappa(q_i, k_j) / (sum_(j) kappa(q_i, k_j)) $

Let $kappa(Q, K)$ denote the matrix of pairwise kernel values, with entries $kappa(q_i, k_j)$.

Define the normalization denominator

$
  D = "diag"( kappa(Q, K) bold(1))
$

Then normalized kernel attention can be written as

$
  Y = D^(-1) kappa(Q, K) V
$

We now focus on $kappa(Q, K) V$ to analyze the complexity.
Note that
$Q, K, V in RR^(n times d)$.

$kappa(Q, K)$ is $RR^(n times d) times RR^(d times n)$, $kappa V$ is $RR^(n times n) times RR^(n times d)$, resulting in a $O(n^2)$ complexity.

The key observation is that, if we can use the associativity to calculate $K^T V$ first, $K^T V$ is $RR^(d times n) times RR^(n times d)$, $Q (K^T V)$ is $RR^(n times d) times RR^(d times d)$, resulting is a $O(n)$ complexity.

However, the $"exp"$ operation in the original $kappa$ stops us from using associativity. In order to exploit the associativity, we need that $kappa$ can be factorized into two respective  matrices of $Q$ and $V$.
To achieve this, kernel-based attention seeks a finite-dimensional feature-map representation of the kernel:

$
  kappa(q_i, k_j) = phi(q_i)^T phi(k_j)
$
$
  kappa(Q, K) = phi(Q) phi(K)^T
$

where $phi: RR^(d) -> RR^r$ is a feature map. Positive-semidefinite kernels admit inner-product representations in feature spaces, which may be infinite-dimensional. Efficient linear attention requires a finite-dimensional representation or approximation.

With this factorization, the unnormalized attention computation becomes

$
  kappa(Q, K) V
  = (phi(Q) phi(K)^T) V
  = phi(Q) (phi(K)^T V)
$

Similarly, we can compute $D$ as
$
  D = "diag"( kappa(Q, K) bold(1)) = "diag"(phi(Q) (phi(K)^T bold(1)))
$

Thus
$
  Y = D^(-1) phi(Q) (phi(K)^T V)
$

The complexity of full-sequence attention without a causal mask is thus reduced to $O(n)$.

For autoregressive inference with a causal mask, each position $t$ can only attend to positions $j <= t$,
$ Y = D^(-1) (M dot.o kappa(Q, K)) V = D^(-1) (M dot.o (phi(Q) phi(K)^T)) V $
$ D = "diag"((M dot.o kappa(Q, K)) bold(1)) = "diag"((M dot.o (phi(Q) phi(K)^T)) bold(1) ) $
Due to the Hadamard product, we can not apply the associativity. However, for each position $t$,
$
  y_t = D^(-1) phi(q_t)^T (phi(K_t)^T V) =
  (phi(q_t)^T sum_(j=1)^t phi(k_j) v_j^T) /
  (phi(q_t)^T sum_(j=1)^t phi(k_j))
$

Directly recomputing these prefix sums at every position would result in $1 + 2 + dots + n = O(n^2)$ complexity. Obviously, we can maintain two recurrent states:

$
  S_t = sum_(j=1)^t phi(k_j) v_j^T,
  quad z_t = sum_(j=1)^t phi(k_j)
$

These can be updated incrementally:

$
  S_t = S_(t-1) + phi(k_t) v_t^T,
  quad z_t = z_(t-1) + phi(k_t)
$

with $S_0 = 0$ and $z_0 = 0$. The attention output is then

$
  y_t = (phi(q_t)^T S_t) / (phi(q_t)^T z_t)
$

Since $phi(q_t) in RR^r$, $S_t in RR^(r times d)$, $z_t in RR^r$, each step requires $O(1)$ time.


Therefore, autoregressive inference over $n$ steps requires $O(n)$ total time and only $O(1)$ memory for the recurrent states. In this architecture, transformers are RNNs.

Different architectures follow two main approaches:

- *Linear Transformer* defines a new kernel through a feature map, allowing exact factorization of the new kernel.
- *Performer*, *RFA* uses randomized feature maps to approximate the original exponential dot-product kernel, aiming to preserve softmax attention while reducing computational complexity.


= Linear Transformer


Linear Transformer adopts a simple feature map:

$
  phi(x) = "ELU"(x) + 1
$

where ELU is applied elementwise. Since $phi(x)$ is positive, the resulting kernel $kappa$ is positive, allowing positive similarities and valid attention normalization.

This defines a new kernel rather than approximating the original exponential dot-product kernel.

*Remark:* Linear Transformer achieves $O(n)$ complexity with or without a causal mask.


= Performer (FAVOR+)

Unlike Linear Transformer, which defines a new kernel, Performer aims to approximate the original exponential dot-product kernel:

$
  kappa(q, k) = exp((q^T k) / sqrt(d))
$

The identity

$
  q^T k = (norm(q+k)^2 - norm(q)^2 - norm(k)^2) / 2
$

implies
$
  kappa (q, k)
  = exp(-norm(q)^2 / (2 sqrt(d))) exp(-norm(k)^2 / (2 sqrt(d)))
  exp(norm(q+k)^2 / (2 sqrt(d)))
$
Note that if $omega tilde.op cal(N) (0, I)$,

$
  EE_omega [exp(omega^T x)] = exp(norm(x)^2 / 2)
$
Thus
$
  kappa(q, k) &approx exp(-norm(q)^2 / (2 sqrt(d))) exp(-norm(k)^2 / (2 sqrt(d))) exp((omega^T (q + k))/ d^(1/4)) \ &= exp(-norm(q)^2 / (2 sqrt(d))) exp(-norm(k)^2 / (2 sqrt(d))) exp((omega^T q) / d^(1/4)) exp((omega^T k) / d^(1/4))
$
Define

$
  psi_omega (x)
  = exp(
    (omega^T x) / d^(1/4)
    - norm(x)^2 / (2 sqrt(d))
  )
$

$ kappa(q, k) approx psi_omega (q)^T psi_omega (k) $
Sample multiple $omega tilde cal(N)(0, I): omega_1, omega_2, dots, omega_r$ to reduce error.

$
  phi(x) = 1 / sqrt(r) vec(
    psi_(omega_1) (x),
    dots.v,
    psi_(omega_r) (x)
  )
$


$
  kappa(q, k) approx 1/r sum_(i=1)^r psi_(omega_i) (q)^T psi_(omega_i) (k)
  = phi(q)^T phi(k)
$

Performer introduces FAVOR+ (*Fast Attention Via Positive Orthogonal Random Features*), which uses orthogonalized random projections with appropriate scaling to reduce estimation variance while preserving the required marginal distributions.

$phi (x)$ is strictly positive, ensuring positive kernel estimates and valid attention normalization.

*Remark:* Performer approximates the original softmax kernel using positive orthogonal random features. Performer achieves $O(n)$ complexity with or without a causal mask.

= Flash Linear Attention (FLA)

Linear attention has an attractive recurrent formulation, but a linear-time algorithm is not necessarily a fast GPU algorithm. FLA aims to improve the parallelism of linear attention with a causal mask.

To see the motivation, recall

$
  S_t = S_(t-1) + phi(k_t) v_t^T,
  quad z_t = z_(t-1) + phi(k_t)
$

Sequential dependencies of recurrent states limit parallelism when all training tokens are available.


We first split the sequence in chunks. Let the chunk size be $B$, and define $b_c = c B$ as the last token position of chunk $c$. Write $Q^(c), K^(c), V^(c)$ for the query, key, and value matrices of chunk $c$.

The state at the end of chunk $c$ satisfies

$
  S_(b_c) = S_(b_(c-1)) + phi(K^(c))^T V^(c)
$
We now update the boundary state once per chunk.

The boundary states can be computed in a recurrent way. Given these states, the outputs of different chunks can be computed in parallel.


For a token $t$ within chunk $c$, its state can be decomposed into two parts:

$
  S_t
  = S_(b_(c-1))
  + sum_(j=b_(c-1)+1)^t phi(k_j) v_j^T
$
$
  z_t
  = z_(b_(c-1))
  + sum_(j=b_(c-1)+1)^t phi(k_j)
$

Therefore,

$ phi(q_t)^T S_t = phi(q_t)^T S_(b_(c-1)) + phi(q_t)^T sum_(j=b_(c-1)+1)^t phi(k_j) v_j^T $
$ phi(q_t)^T z_t = phi(q_t)^T z_(b_(c-1)) + phi(q_t)^T sum_(j=b_(c-1)+1)^t phi(k_j) $
For the whole chunk,
$
  N^c = mat(phi(q_t)^T S_t; phi(q_(t+1))^T S_(t+1); phi(q_(t+2))^T S_(t+2)) = phi(Q^c) S_(b_(c-1)) + (M dot.o (phi(Q^c) phi(K^c)^T)) V^c
$
$
  D^c = "diag"mat(phi(q_t)^T z_t; phi(q_(t+1))^T z_(t+1); phi(q_(t+2))^T z_(t+2)) = "diag"(phi(Q^c) z_(b_(c-1)) + (M dot.o (phi(Q^c) phi(K^c)^T)) bold(1))
$
$ Y^c = (D^c)^(-1) N^c $

The first term represents *inter-chunk memory*, while the second represents *intra-chunk causal attention*.

*Remark:* FLA addresses the sequential dependence of linear attention and improve its parallelism through chunking.

= Random Feature Attention (RFA)

RFA returns to the problem addressed by Performer: approximating the softmax kernel.

Write the scaled exponential dot-product kernel. With a scale parameter $sigma > 0$,

$
  kappa (q, k) = exp((q^T k) / sigma^2)
$

The identity

$
  q^T k = (norm(q)^2 + norm(k)^2 - norm(q-k)^2) / 2
$

implies

$
  kappa (q, k)
  = exp(norm(q)^2 / (2 sigma^2)) exp(norm(k)^2 / (2 sigma^2))
  exp(-norm(q-k)^2 / (2 sigma^2))
$

Note that if $omega tilde cal(N)(0, sigma^(-2) I)$,

$
  EE_omega [cos(omega^T (q-k))]
  = exp(-norm(q-k)^2 / (2 sigma^2))
$
Thus
$
  kappa(q, k) &approx exp(norm(q)^2 / (2 sigma^2)) exp(norm(k)^2 / (2 sigma^2)) cos(omega^T (q-k)) \ &= exp(norm(q)^2 / (2 sigma^2)) exp(norm(k)^2 / (2 sigma^2)) (cos omega^T q cos omega^T k + sin omega^T q sin omega^T k) \ &= exp(norm(q)^2 / (2 sigma^2)) exp(norm(k)^2 / (2 sigma^2)) mat(cos omega^T q; sin omega^T q)^T mat(cos omega^T k; sin omega^T k)
$

Define
$ psi_omega (x) = exp(norm(x)^2 / (2 sigma^2)) mat(cos omega^T x; sin omega^T x) $

$ kappa(q, k) approx psi_omega (q)^T psi_omega (k) $

Sample multiple $omega tilde cal(N)(0, sigma^(-2) I): omega_1, omega_2, dots, omega_r$ to reduce error.
$ phi(x) = 1/sqrt(r) mat(psi_omega_1 (x); dots.v; psi_omega_r (x)) $
$ kappa(q, k) approx 1/r sum_(i=1)^r psi_omega_i (q)^T psi_omega_i (k) = phi (q)^T phi (k) $

Unlike FAVOR+, a finite Fourier-feature estimate can be negative, so normalization requires care.

RFA also supports recency bias through an optional gate.

$
  S_t & = g_t S_(t-1) + (1- g_t) phi(k_t) v_t^T \
  z_t & = g_t z_(t-1) + (1- g_t) phi(k_t)
$

where $g_t$ discounts older information when $0 <= g_t <= 1$.

*Remark:* RFA approximates softmax through random Fourier features and adds optional gated recency. RFA achieves $O(n)$ complexity with or without a causal mask.
