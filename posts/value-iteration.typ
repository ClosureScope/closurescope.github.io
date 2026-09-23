#import "../typst/template.typ": *
#show: article.with(
  title: "Value Iteration",
  date: "2026-09-23",
  category: "Reinforcement Learning",
)

= Bellman Expectation Equation
#definition[Value Function][
  $ V^pi (s_0) = EE_(tau) [R(tau)] = EE_(tau)[sum_(t=0)^infinity gamma^t r(s_t, a_t)] $
]
Rewrite $V^pi (s_0)$ in a recursive way.

$
  V^pi (s_0) & = EE_(a_0)[ EE_(s_1) [EE_(tau_1)[r(s_0, a_0) + gamma sum_(t=1)^infinity gamma^(t-1) r(s_t, a_t)]]] \
             & = EE_(a_0)[r(s_0, a_0) + gamma EE_(s_1) [EE_(tau_1) [sum_(t=1)^infinity gamma^(t-1) r(s_t, a_t)]]] \
             & = EE_(a_0)[r(s_0, a_0) + gamma EE_(s_1) [V^pi (s_1)] ]
$

We thus derive
#theorem[Bellman Expectation Equation][
  $ V^pi (s_0) = EE_(a_0)[r(s_0, a_0) + gamma EE_(s_1) [V^pi (s_1)] ] $
]
= Policy Evaluation
== Bellman Expectation Operator and Contraction Property
#definition[Bellman Expectation Operator][
  $ (T^pi V)(s) = EE_a [r(s,a) + gamma EE_(s^') [V(s^')]] $
]
#proposition[Contraction Property][
  $ norm(T^pi V - T^pi W)_infinity <= gamma norm(V - W)_infinity $
]

#proof[Contraction Property][

  $
    abs((T^pi V)(s) - (T^pi W)(s)) & = gamma abs(EE_a [EE_(s^') [V(s^') - W(s^')]]) \
                                   & <= gamma EE_a [EE_(s^') [abs(V(s^') - W(s^'))]] \
                                   & <= gamma norm(V - W)_infinity
  $

  Taking the maximum over all states,

  $
    norm(T^pi V - T^pi W)_infinity
    <= gamma norm(V - W)_infinity
  $

]

== Convergence of Policy Evaluation

Policy Evaluation repeatedly applies the Bellman Expectation Operator:
#strategy[Policy Evaluation][
  $
    V_(k+1) = T^pi V_k
  $
]

#theorem[Convergence of Policy Evaluation][
  For any initial value function $V_0$,

  $
    lim_(k -> infinity) (T^pi)^k V_0 = V^pi
  $
]

#proof[Convergence of Policy Evaluation][

  By the Bellman Expectation Equation, $V^pi$ is a fixed point of $T^pi$ i.e.

  $
    V^pi = T^pi V^pi
  $

  Using the contraction property,

  $
    norm(V_(k+1) - V^pi)_infinity & = norm(T^pi V_k - T^pi V^pi)_infinity \
                                  & <= gamma norm(V_k - V^pi)_infinity \
                                  & <= gamma^(k+1) norm(V_0 - V^pi)_infinity
  $

  $
    lim_(k -> infinity) norm(V_k - V^pi)_infinity = 0
  $

  Hence Policy Evaluation converges to $V^pi$


  Moreover, by the Banach Fixed-Point Theorem,
  $T^pi$ has a unique fixed point, which must be $V^pi$
]

#corollary[Bellman Expectation Equation][
  $ V = V^pi <=> V = T^pi V $
]

= Bellman Optimality Equation

#definition[Optimal Value Function][
  Let $cal(M)$ denote the set of all admissible policies,
  including history-dependent and nonstationary policies.

  $
    V^* (s) = sup_(mu in cal(M)) V^mu (s)
  $
]

We use the supremum because the existence of an optimal
policy has not yet been established

#theorem[Bellman Optimality Equation][
  $
    V^* (s)
    = max_(a in cal(A)) (
      r(s, a) + gamma EE_(s^') [V^* (s^')]
    )
  $
]
We will leave the proof in the next section.

= Value Iteration

== Bellman Optimality Operator and Contraction Property

#definition[Bellman Optimality Operator][
  $
    (T^* V)(s)
    = max_(a in cal(A)) (
      r(s, a) + gamma EE_(s^') [V(s^')]
    )
  $
]

#proposition[Contraction Property][
  $
    norm(T^* V - T^* W)_infinity
    <= gamma norm(V - W)_infinity
  $
]

#proof[Contraction Property][

  Recall that for any finite collections of real numbers,

  $
    abs(max_i x_i - max_i y_i)
    <= max_i abs(x_i - y_i)
  $


  $
    abs((T^* V)(s) - (T^* W)(s)) & <= gamma max_(a in cal(A))
                                   abs(EE_(s^') [V(s^') - W(s^')]) \
                                 & <= gamma max_(a in cal(A))
                                   EE_(s^') [abs(V(s^') - W(s^'))] \
                                 & <= gamma norm(V - W)_infinity
  $

  Taking the maximum over all states,

  $
    norm(T^* V - T^* W)_infinity
    <= gamma norm(V - W)_infinity
  $
]

We now prove the Bellman Optimality Equation
by identifying the unique fixed point of $T^*$
with the optimal value function $V^*$.

#proof[Bellman Optimality Equation][

  By the Banach Fixed-Point Theorem, exists unique V s.t.

  $
    V = T^* V
  $

  We only need to prove that $V$ is optimal.

  We prove $V = V^*$ by establishing both directions of the inequality.

  *Step 1: Prove that $V <= V^*$*
  #intuition[][We want to show that $V$ is a value function corresponding to some policy $pi$, thus must be smaller than the optimal value function $V^*$]



  Construct a deterministic stationary greedy policy

  $
    pi (s) in "argmax"_(a in cal(A)) (
      r(s, a) + gamma EE_(s^') [V(s^')]
    )
  $

  Such policy exists since the action space is finite so that the maximum
  is attained in every state. Thus
  $
    (T^pi V)(s) & = r(s, pi(s)) + gamma EE_(s^') [V(s^')]
                  = (T^* V)(s)
                  = V(s)
  $


  By the uniqueness of the fixed point of the Bellman Expectation Operator,

  $
    V = V^(pi)
  $

  Since $pi$ is an admissible policy,

  $
    V = V^(pi) <= V^*
  $

  *Step 2: Prove that $V >= V^*$*

  Since $V = T^* V$, for every state $s$ and action $a$,

  $
    V(s) >= r(s, a) + gamma EE_(s^') [V(s^')]
  $

  Consider an arbitrary admissible policy $mu in cal(M)$. Apply the inequality recursively at each step.

  $
    V(s_0) >= EE_(tau) [
      sum_(t=0)^(n-1) gamma^t r(s_t, a_t)
      + gamma^n V(s_n)
    ]
  $

  Since the state space is finite, $V$ is bounded.
  Taking the limit as $n -> infinity$ gives

  $
    V(s_0) & >= EE_(tau) [
               sum_(t=0)^infinity gamma^t r(s_t, a_t)
             ]
             = V^mu (s_0)
  $

  Since this holds for every admissible policy,

  $
    V(s) >= sup_(mu in cal(M)) V^mu (s)
    = V^* (s)
  $
]
#corollary[Bellman Optimality Equation][
  $ V = V^* <=> V = T^* V $
]

== Convergence of Value Iteration

Value Iteration repeatedly applies the Bellman Optimality Operator.

#strategy[Value Iteration][
  $
    V_(k+1) = T^* V_k
  $
]

#theorem[Convergence of Value Iteration][
  For any initial value function $V_0$,

  $
    lim_(k -> infinity) (T^*)^k V_0 = V^*
  $
]

#proof[Convergence of Value Iteration][

  By the Bellman Optimality Equation, $V^*$ is a fixed point of $T^*$ i.e.
  $ V^* = T^* V^* $


  Using the contraction property,

  $
    norm(V_(k+1) - V^*)_infinity & = norm(T^* V_k - T^* V^*)_infinity \
                                 & <= gamma norm(V_k - V^*)_infinity \
                                 & <= gamma^(k+1) norm(V_0 - V^*)_infinity
  $

  $
    lim_(k -> infinity) norm(V_k - V^*)_infinity = 0
  $

  Hence Value Iteration converges to $V^*$.
]
