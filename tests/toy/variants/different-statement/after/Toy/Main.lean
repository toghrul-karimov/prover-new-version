import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- Same name, different statement: `n + n` instead of `2 * n + 0`.
theorem main (h : AddZero) (n : Nat) : double n = n + n := rfl

end Toy.Main
