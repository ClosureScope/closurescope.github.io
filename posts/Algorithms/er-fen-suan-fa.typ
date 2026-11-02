#import "../../typst/template.typ": *
#show: article.with(
  title: "二分算法",
)

二分算法适合解决：

谓词对变量具有单调性，给定变量取值容易判定谓词真值，搜索谓词分界点对应的变量

时间复杂度：$O(log n)$

也就是说，我们有形如
#align(center)[
  `[False, False, ..., False, True, ..., True, True]`
]
或
#align(center)[
  `[True, True, ..., True, False, ..., False, False]`
]
的单调布尔值数组，我们需要搜索分界点对应的下标。需要注意的是，上述数组只是想象出来的解空间对应的数组，并不一定是一个真实的数组。

以在单调增数组中找出第一个`True`的下标为例，
#align(center)[
  `[False, False, ..., False, True, ..., True, True]`
]
使用`left`, `right`来维护`(left, right)`的二分区间，循环不变量为`check(left) == False`和`check(right) == True`，二分区间内即那些还没确定对应真值的下标。
```python
def binary_search(check: Callable[[int], bool]) -> int:
    left = MIN # 能确定 check(MIN) == False
    right = MAX # 能确定 check(MAX) == True
    while left + 1 < right: # 开区间不为空
        mid = (left + right) // 2
        if check(mid): # 维护 check(left) == False and check(right) == True
            right = mid
        else:
            left = mid
    # 此时 (left, right) 恰好跨在分界点上，left 对应最后一个 False, right 对应第一个 True
    return right

```
= 二分查找
以单调增整数数组为例，我们需要查找数组中$>= x$的第一个元素的下标。只需定义`check`即可。
```python
def lower_bound(nums: list[int], x: int) -> int:
    check = lambda i: nums[i] >= x
    return binary_search(check)
```
常见问题均可转化为对于`lower_bound`的调用
#three-line-table[
  |要求|写法|
  | --- | --- |
  |$>=x$的第一个元素的下标|`lower_bound(nums, x)`|
  |$>x$的第一个元素的下标|`lower_bound(nums, x + 1)`|
  |$<x$的最后一个元素的下标|`lower_bound(nums, x) - 1`|
  |$<=x$的最后一个元素的下标|`lower_bound(nums, x + 1) - 1`|
  |$<x$的元素个数|`lower_bound(nums, x)`|
  |$<=x$的元素个数|`lower_bound(nums, x + 1)`|
  |$>=x$的元素个数|`n - lower_bound(nums, x)`|
  |$>x$的元素个数|`n - lower_bound(nums, x + 1)`|
  |$=x$的元素个数|`lower_bound(nums, x + 1) - lower_bound(nums, x)`|
  |$[L, R]$内元素个数|`lower_bound(nums, R + 1) - lower_bound(nums, L)`|

]
= 二分答案
== 求最小/求最大
即上文所述的二分算法
== 最小化最大值/最大化最小值
最小化最大值即为求最小，即判定用于试探的最大值是否存在对应解

最大化最小值即为求最大，即判定用于试探的最小值是否存在对应解
== 第$k$小/大
第$k$小等价于：求最小的$x$，使得满足$<=x$的元素至少有$k$个

第$k$大等价于：求最大的$x$，使得满足$>=x$的元素至少有$k$个
