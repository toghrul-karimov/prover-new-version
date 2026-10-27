import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- Definitionally equal to the approved statement (`2 * n + 0` reduces to `2 * n`),
-- but written differently. Does the comparator accept it? Our per-task audit would (defeq check).
theorem main (h : AddZero) (n : Nat) : double n = 2 * n := Toy.Lemmas.Double.double_eq n

end Toy.Main
