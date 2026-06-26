#include <iostream>
#include <string>
#include <stdexcept>
int main() {
  try { throw std::runtime_error("exceptions work"); }
  catch (const std::exception& e) { std::cout << "hello from C++ (musl): " << e.what() << "\n"; }
  return 0;
}
