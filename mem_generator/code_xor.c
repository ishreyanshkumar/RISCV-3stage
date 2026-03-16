#include <stdio.h>

int main()
{
  int a = 0xAA; // 10101010
  int b = 0x55; // 01010101
  int result;

  result = a ^ b; // Expected: 0xFF (255)

  return result;
}