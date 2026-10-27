import Mathlib.Analysis.SpecialFunctions.Exp

/-! A definition that pulls in a realistic slice of Mathlib (real analysis). -/

namespace ToyM.Defs.Basic

/-- `exp x + x ^ 2`. -/
noncomputable def f (x : ℝ) : ℝ := Real.exp x + x ^ 2

end ToyM.Defs.Basic
