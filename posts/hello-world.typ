#import "../typst/template.typ": *
#show: article.with(
  title: "Hello, Typst · 从一个梯度开始",
  date: "2026-09-23",
  description: "一个最小二乘梯度的例子。",
)

= 从一个梯度开始

这是我的第一篇技术文章。正文、数学公式和代码都写在同一个 Typst 文件里。
以最小二乘问题为例，设 $A$ 是矩阵，$x$ 和 $b$ 是向量。
对于目标函数 $f(x) = 1/2 norm(A x - b)^2$，它的梯度为：

$
  nabla f(x) = A^T (A x - b)
$

== 用 Python 表达

下面的函数使用矩阵乘法直接计算梯度；输入可以是 NumPy 数组。

```python
def gradient(A, x, b):
    residual = A @ x - b
    return A.T @ residual
```

#definition[梯度][梯度指出函数增长最快的方向，沿负梯度移动可以寻找较小的函数值。]

== 配一张图

图片同样由 Typst 引用，资源放在项目的 assets 目录中。

#image("../assets/gradient.svg", alt: "凸函数曲线上的点沿负梯度方向向最低点移动")
