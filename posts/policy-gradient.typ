#import "../typst/template.typ": *
#show: article.with(
  title: "Policy Gradient",
  date: "2026-09-28",
  category: "Reinforcement Learning",
)

= Policy Gradient Theorem
== Background
Consider a parameterized stochastic policy $ pi_theta (a | s) $

The goal of policy optimization is to maximize the expected return of the policy. Suppose the initial state is fixed as $s_0$. We define the objective function
$ J(theta) := V^(pi_theta ) (s_0) = EE_tau [G(tau) | s_0] $
To maximize $J(theta)$, it is necessary to compute $ nabla_theta J(theta) $


== Trajectory Probability

A trajectory

$
  tau
  = (s_0, a_0, s_1, a_1, ..., s_T)
$

is generated according to

$
  P_theta (tau | s_0)
  =
  product_(t=0)^(T-1)
  pi_theta (a_t | s_t)
  P(s_(t+1) | a_t)
$

Hence,

$
  J(theta)
  =
  sum_tau
  P_theta (tau | s_0)
  G(tau)
$

Differentiating with respect to $theta$,

$
  nabla_theta J(theta)
  =
  sum_tau
  G(tau)
  nabla_theta P_theta (tau | s_0)
$

The difficulty is that a trajectory contains stochastic action sampling and
stochastic environment transitions. Therefore, we cannot simply backpropagate
through a sampled trajectory as if it were an ordinary deterministic computation
graph.

== Log-Derivative Trick

Using the identity

$
  nabla_theta P_theta (tau)
  =
  P_theta (tau)
  nabla_theta log P_theta (tau),
$

we obtain

$
  nabla_theta J(theta)
  =
  sum_tau
  P_theta (tau | s_0)
  G(tau)
  nabla_theta log P_theta (tau | s_0)
$

Therefore,

$
  nabla_theta J(theta)
  =
  EE_(tau) [
    G(tau)
    nabla_theta log P_theta (tau | s_0)
  ]
$

== Removing the Environment Dynamics

Expanding the log trajectory probability gives

$
  log P_theta (tau | s_0)
  =
  sum_(t=0)^(T-1)
  log pi_theta (a_t | s_t)
  +
  sum_(t=0)^(T-1)
  log P(s_(t+1) | a_t)
$

The environment transition probability

$
  P(s_(t+1) | a_t)
$

does not depend on the policy parameters $theta$. Therefore,

$
  nabla_theta
  log P(s_(t+1) | a_t)
  =
  0
$

Thus,

$
  nabla_theta
  log P_theta (tau | s_0)
  =
  sum_(t=0)^(T-1)
  nabla_theta
  log pi_theta (a_t | s_t)
$

Substituting this back,

$
  nabla_theta J(theta)
  =
  EE_tau [
    G(tau)
    sum_(t=0)^(T-1)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$

Therefore, the environment dynamics do not need to be differentiable.
Only the policy must be differentiable with respect to $theta$

== Reward-to-Go
We now show that the rewards before time $t$ have zero expected contribution.
$
  nabla_theta J(theta)
  =
  sum_(t=0)^(T-1) EE_tau [
    G(tau)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$
For a fixed $t$, write

$
  G(tau)
  =
  sum_(k=0)^(t-1) gamma^k R_k
  +
  sum_(k=t)^(T-1) gamma^k R_k
$

Let $tau_t$ denote the suffix of $tau$ starting with $(s_t, a_t)$, so
$tau_0 = tau$.
Its return is

$
  G(tau_t)
  :=
  sum_(k=t)^(T-1)
  gamma^(k-t) R_k
$

Let $tau_(< t)$ denote the trajectory prefix before sampling $a_t$:

$
  tau_(< t)
  :=
  (s_0, a_0, ..., s_t)
$


$
  EE_tau [
    G(tau)
    nabla_theta
    log pi_theta (a_t | s_t)
  ] & =
      EE_tau [
        (
          sum_(k=0)^(t-1) gamma^k R_k
        )
        nabla_theta
        log pi_theta (a_t | s_t)
      ] \
    & +
      EE_tau [
        (
          sum_(k=t)^(T-1) gamma^k R_k
        )
        nabla_theta
        log pi_theta (a_t | s_t)
      ]
$

We now show the first term is $0$.
$
  EE_tau [
    (
      sum_(k=0)^(t-1) gamma^k R_k
    )
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
  =
  EE_(tau_(< t)) [
    (
      sum_(k=0)^(t-1) gamma^k R_k
    )
    EE_(a_t) [
      nabla_theta
      log pi_theta (a_t | s_t)
      |
      tau_(< t)
    ]
  ]
$



$
  EE_(a_t) [
    nabla_theta
    log pi_theta (a_t | s_t)
    |
    tau_(< t)
  ] & =
      sum_a
      pi_theta (a | s_t)
      nabla_theta
      log pi_theta (a | s_t) \
    & =
      sum_a
      nabla_theta
      pi_theta (a | s_t) \
    & =
      nabla_theta
      sum_a
      pi_theta (a | s_t) \
    & =
      nabla_theta 1
      =
      0
$

Therefore,

$
  EE_tau [
    (
      sum_(k=0)^(t-1) gamma^k R_k
    )
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
  =
  0
$

Thus,

$
  EE_tau [
    G(tau)
    nabla_theta
    log pi_theta (a_t | s_t)
  ] & =
      EE_tau [
        (
          sum_(k=t)^(T-1) gamma^k R_k
        )
        nabla_theta
        log pi_theta (a_t | s_t)
      ] \
    & =
      EE_tau [
        gamma^t
        G(tau_t)
        nabla_theta
        log pi_theta (a_t | s_t)
      ]
$

$
  nabla_theta J(theta)
  =
  EE_tau [
    sum_(t=0)^(T-1)
    gamma^t
    G(tau_t)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$

Thus, for the gradient term associated with $a_t$, only rewards from time $t$
onward matter in expectation.

== From Return to Action Value

By definition,

$
  Q^(pi_theta) (s, a)
  =
  EE_(tau) [
    G(tau)
    |
    s_0, a_0
  ]
$

Using the law of total expectation,

$
  EE_(tau) [
    G(tau_t)
    nabla_theta
    log pi_theta (a_t | s_t)
  ] & =
      EE_(s_t, a_t) [EE_(tau) [ G(tau_t)
          nabla_theta
          log pi_theta (a_t | s_t) | s_t, a_t] ] \
    & =
      EE_(s_t, a_t) [
        Q^(pi_theta) (s_t, a_t)
        nabla_theta
        log pi_theta (a_t | s_t)
      ]
$

$
  nabla_theta J(theta)
  =
  sum_(t=0)^(T-1)
  gamma^t
  EE_(s_t, a_t) [
    Q^(pi_theta) (s_t, a_t)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$

Define the unnormalized discounted state-visitation measure

$
  d_gamma^(pi_theta) (s)
  :=
  sum_(t=0)^(T-1)
  gamma^t
  P(s_t = s | pi_theta).
$


$
  nabla_theta J(theta) & =
                         sum_(t=0)^(T-1)
                         gamma^t
                         sum_s P(s_t = s) sum_a pi_theta (a | s)
                         Q^(pi_theta) (s_t, a_t)
                         nabla_theta
                         log pi_theta (a_t | s_t) \
                       & =
                         sum_s
                         d_gamma^(pi_theta) (s)
                         sum_a
                         pi_theta (a | s)
                         Q^(pi_theta) (s, a)
                         nabla_theta
                         log pi_theta (a | s)
$

#theorem[Policy Gradient Theorem][ $
  nabla_theta J(theta)=
  sum_s
  d_gamma^(pi_theta) (s)
  sum_a
  pi_theta (a | s)
  Q^(pi_theta) (s, a)
  nabla_theta
  log pi_theta (a | s)
$]

== Introducing a Baseline

#lemma[][
  For any function $b(s)$ that depends only on the state,

  $
    EE_(a) [
      b(s)
      nabla_theta
      log pi_theta (a | s)
      |
      s
    ]
    =
    0
  $
]

#proof[][
  $
    sum_a
    pi_theta (a | s)
    b(s)
    nabla_theta
    log pi_theta (a | s) & =
                           b(s)
                           sum_a
                           nabla_theta
                           pi_theta (a | s) \
                         & =
                           b(s)
                           nabla_theta
                           sum_a
                           pi_theta (a | s) \
                         & =
                           b(s)
                           nabla_theta 1
                           =
                           0
  $
]

From the previous result,

$
  nabla_theta J(theta)
  =
  sum_(t=0)^(T-1)
  gamma^t
  EE_(s_t, a_t) [
    Q^(pi_theta) (s_t, a_t)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$

The natural choice is

$
  b(s)
  =
  V^(pi_theta) (s)
$

Define the advantage

$
  A^(pi_theta) (s, a)
  :=
  Q^(pi_theta) (s, a)
  -
  V^(pi_theta) (s)
$

We obtain

$
  nabla_theta J(theta)
  =
  sum_(t=0)^(T-1)
  gamma^t
  EE_(s_t, a_t) [
    A^(pi_theta) (s_t, a_t)
    nabla_theta
    log pi_theta (a_t | s_t)
  ]
$

This is the form commonly used in actor-critic methods.

== Interpretation

The term

$
  A^(pi_theta )(s, a)
  nabla_theta
  log pi_theta (a | s)
$

has a simple interpretation.

$nabla_theta log pi_theta (a | s)$ points in the direction of the steepest increase of $log pi_theta (a | s)$.

If $A^(pi_theta )(s, a) > 0$,

then action $a$ performs better than the policy's average behavior at state
$s$. Therefore, the update increases $pi_theta (a | s)$.

If $A^(pi_theta )(s, a) < 0$,

then the action $a$ performs worse than average, so the update decreases $pi_theta (a | s)$.
