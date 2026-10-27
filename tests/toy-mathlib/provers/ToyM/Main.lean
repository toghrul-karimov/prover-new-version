import ToyM.Defs.Basic
import Mathlib.Tactic.Positivity

namespace ToyM.Main
open ToyM.Defs.Basic

/-- `f` is positive everywhere. -/
theorem f_pos (x : ℝ) : 0 < f x := by
  unfold f
  positivity

end ToyM.Main
