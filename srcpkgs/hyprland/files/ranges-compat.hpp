#pragma once
#if __cplusplus >= 202002L
#include <algorithm>
#include <functional>
#include <iterator>
#include <ranges>

#if !defined(__cpp_lib_ranges_contains)
namespace std {
    namespace ranges {
        struct __compat_contains_fn {
            template <std::ranges::input_range R, class T, class Proj = std::identity>
            constexpr bool operator()(R&& r, const T& value, Proj proj = {}) const {
                for (auto&& e : r)
                    if (std::invoke(proj, e) == value)
                        return true;
                return false;
            }
        };
        inline constexpr __compat_contains_fn contains{};
    }
}
#endif

#if !defined(__cpp_lib_ranges_starts_ends_with)
namespace std {
    namespace ranges {
        struct __compat_starts_with_fn {
            template <std::ranges::input_range R1, std::ranges::input_range R2>
            constexpr bool operator()(R1&& r1, R2&& r2) const {
                auto i1 = std::ranges::begin(r1);
                auto e1 = std::ranges::end(r1);
                auto i2 = std::ranges::begin(r2);
                auto e2 = std::ranges::end(r2);
                for (; i2 != e2; ++i1, ++i2)
                    if (i1 == e1 || !(*i1 == *i2))
                        return false;
                return true;
            }
        };
        inline constexpr __compat_starts_with_fn starts_with{};
    }
}
#endif
#endif
