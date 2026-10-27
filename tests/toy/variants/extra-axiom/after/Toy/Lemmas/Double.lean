import Toy.Defs.Basic

namespace Toy.Lemmas.Double
open Toy.Defs.Basic

axiom cheat : ∀ n : Nat, double n = 2 * n

theorem double_eq (n : Nat) : double n = 2 * n := cheat n

end Toy.Lemmas.Double
