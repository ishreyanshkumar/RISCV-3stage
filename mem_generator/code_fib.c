#include <stdio.h>

int main()
{
  int n = 7;
  int a = 0, b = 1, next, i;

  if (n == 0)
    return a;

  for (i = 2; i <= n; i++)
  {
    next = a + b;
    a = b;
    b = next;
  }
  return b; // Result will be in Register 15
}