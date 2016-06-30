﻿module IntegralsModule
export computeValueOverlap, doublefactorial, computeElectronRepulsionIntegral, KineticIntegral, NuclearAttractionIntegral
using ..BaseModule
using ..BasisFunctionsModule
using ..AtomModule
using ..GeometryModule
using ..DocumentationModule
using ..ShellModule
using ProgressMeter

ProgressMeter.printover(STDOUT," + (GSL........................")
using GSL
ProgressMeter.printover(STDOUT," + IntegralsModule.............")


doublefactorial(n::Int) = prod(n:-2:1)

"""
I_x = Integrate[x^m Exp[-ζ x^2], {x,-∞,∞}] (acc. to Fundament. of Mol. Integr. Eval. by Fermann, Valeev)
"""
function GaussianIntegral1D(mqn::Int,exponent::Float64)
  m = mqn
  ζ = exponent

  if (mqn%2!=0) # integral over uneven function
    return 0 
  else
    return (doublefactorial(m-1)*sqrt(π)) / ((2ζ)^(m/2)*sqrt(ζ))
  end
end
@doc GenericCitation("Fundament. of Mol. Integr. Eval. by Fermann, Valeev") GaussianIntegral1D


function GaussianIntegral1D(mqn::Int,exponent::Float64)
  # I_x = Integrate[x^m Exp[-ζ x^2], {x,-∞,∞}] (acc. to Mathematica 9)
  m = mqn
  ζ = exponent

  if (mqn%2!=0) # integral over uneven function
    return 0 
  else
    t=(m+1)/2
    return ζ^(-t) * gamma(t)
  end
end

#function FundamentalIntegral(
#  pgb1::PrimitiveGaussianBasisFunction,
#  pgb2::PrimitiveGaussianBasisFunction,
#  func::Function,
#  pgb3::PrimitiveGaussianBasisFunction,
#  pgb4::PrimitiveGaussianBasisFunction)
#  # (pgb1(x1) pgb2(x1) | func(x1,x2) | pgb3(x2) pgb4(x2) )
#  # pgb1..4 are considered s-Functions
#  # acc. to Molecular Integrals of Gaussian Basis Functions by Gill
#
#  # I = (π G_AB G_CD) / ( 2(ζ η)^(3/2) R^3 ) Integrate[u Sin[u] Exp[-u^2/(4T)] FT[f][u/R],{u,0,∞}]
#end

function GaussProductFundamental(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction)
  # Fundamental means primitives are taken as s-Functions
  # K Exp[-γ r^2_P] = pgb1 * pgb2 (acc. to Fundament. of Mol. Integr. Eval. by Fermann, Valeev)

  α1 = pgb1.exponent
  α2 = pgb2.exponent
  A  = pgb1.center
  B  = pgb2.center

  γ = α1 + α2
  P = (α1*A + α2*B) / γ
  AB = distance(A,B)
  K = exp(-α1*α2*AB^2/γ)

  return (K,P,γ)
end

type PolynomialFactors
  x::Array{Tuple{Float64,Int},1} # Float64*x^Int
  y::Array{Tuple{Float64,Int},1} # Float64*y^Int
  z::Array{Tuple{Float64,Int},1} # Float64*z^Int
end

function GaussProductPolynomialFactor(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction)
  # _Sum_K[f_k r^k]_ K Exp[-γ r^2_P] = pgb1 * pgb2 (acc. to Fundament. of Mol. Integr. Eval. by Fermann, Valeev)

  A  = pgb1.center
  B  = pgb2.center
  (K,P,γ) = GaussProductFundamental(pgb1,pgb2)

  #factors = PolynomialFactors(Array(Tuple{Float64,Int},pgb1.mqn.x+pgb2.mqn.x),Array(Tuple{Float64,Int},pgb1.mqn.y+pgb2.mqn.y),Array(Tuple{Float64,Int},pgb1.mqn.z+pgb2.mqn.z))
  factors = PolynomialFactors(Tuple{Float64,Int}[],Tuple{Float64,Int}[],Tuple{Float64,Int}[])
  for (xyz in 1:3)
    l1 = getfield(pgb1.mqn,xyz)
    l2 = getfield(pgb2.mqn,xyz)
    sizehint!(getfield(factors,xyz),1+l1+l2)
    for k in 0:l1+l2
      f = 0.::Float64
      for q in max(-k,k-2l2):2:min(k,2l1-k)
	i = (k+q) ÷ 2
	j = (k-q) ÷ 2
	f += binomial(l1,i) * binomial(l2,j) * getfield((P-A),xyz)^(l1-i) * getfield((P-B),xyz)^(l2-j)
      end
      #ij = [((k+q) ÷ 2,(k-q) ÷ 2) for q in max(-k,k-2l2):2:min(k,2l1-k)]
      #f = sum([binomial(l1,i) * binomial(l2,j) * (P-A).(xyz)^(l1-i) * (P-B).(xyz)^(l2-j) for(i,j) in ij])
      push!(getfield(factors,xyz),(f,k))
    end
  end

  return factors
end

function computeValueOverlap(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction)
  # S_ij = Integrate[phi_i(r) phi_j(r),{r el R}] (acc. to Fundament. of Mol. Integr. Eval. by Fermann, Valeev)

  (K,P,γ) = GaussProductFundamental(pgb1,pgb2)
  factors = GaussProductPolynomialFactor(pgb1,pgb2)

  Ix = sum([f*GaussianIntegral1D(i,γ) for (f,i) in factors.x])
  Iy = sum([f*GaussianIntegral1D(i,γ) for (f,i) in factors.y])
  Iz = sum([f*GaussianIntegral1D(i,γ) for (f,i) in factors.z])
  return K*Ix*Iy*Iz::Float64
end

function computeValueOverlap(
  cgb1::ContractedGaussianBasisFunction,
  cgb2::ContractedGaussianBasisFunction)

  integral = 0.::Float64
  for (coeff1,pgb1) in zip(cgb1.coefficients,cgb1.primitiveBFs)
    for (coeff2,pgb2) in zip(cgb2.coefficients,cgb2.primitiveBFs)
      integral += coeff1*coeff2*computeValueOverlap(pgb1,pgb2)
    end
  end
  return integral::Float64
end

function computeMatrixOverlap(sh1::Shell,sh2::Shell)
  return [computeValueOverlap(cgb1,cgb2) for cgb1 in expandShell(sh1), cgb2 in expandShell(sh2)]
end

function incrmqn(mqn::MQuantumNumber,xyz::Symbol,inc::Int)
  mqn_t = [mqn.x,mqn.y,mqn.z]
  xyznum = Dict(:x => 1, :y => 2, :z => 3)
  num = xyznum[xyz]
  mqn_t[num] += inc
  return MQuantumNumber(mqn_t[1],mqn_t[2],mqn_t[3])
end

function KineticIntegral(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction)
  #Ix + Iy + Iz = (pgb1 | 1/2 ∇^2 | pgb2) 
  #Ix = 1/2 l1 l2 <-1|-1> + 2 α1 α2 <+1|+1> - α1 l2 <+1|-1> - α2 l1 <-1|+1>
  #(acc. to Fundamentals of Mol. Integr. Eval. by Fermann, Valeev (eq. 4.1 + 4.13))

  integral = 0.::Float64

  for (xyz in (:x,:y,:z))
    pgb1decr = deepcopy(pgb1)
    pgb1decr.mqn = incrmqn(pgb1.mqn,xyz,-1)
    pgb1incr = deepcopy(pgb1)
    pgb1incr.mqn = incrmqn(pgb1.mqn,xyz,1)

    pgb2decr = deepcopy(pgb2)
    pgb2decr.mqn = incrmqn(pgb2.mqn,xyz,-1)
    pgb2incr = deepcopy(pgb2)
    pgb2incr.mqn = incrmqn(pgb2.mqn,xyz,1)

    l1 = pgb1.mqn.(xyz)
    l2 = pgb2.mqn.(xyz)
    α1 = pgb1.exponent
    α2 = pgb2.exponent

    if(l1*l2!=0) integral += (1/2*l1*l2) * computeValueOverlap(pgb1decr,pgb2decr) end
                 integral += (2*α1*α2)   * computeValueOverlap(pgb1incr,pgb2incr)
    if(l2   !=0) integral += (-α1*l2)    * computeValueOverlap(pgb1incr,pgb2decr) end
    if(l1   !=0) integral += (-l1*α2)    * computeValueOverlap(pgb1decr,pgb2incr) end
  end

  return integral::Float64
end

function KineticIntegral(
  cgb1::ContractedGaussianBasisFunction,
  cgb2::ContractedGaussianBasisFunction)

  integral = 0.::Float64
  for (coeff1,pgb1) in zip(cgb1.coefficients,cgb1.primitiveBFs)
    for (coeff2,pgb2) in zip(cgb2.coefficients,cgb2.primitiveBFs)
      integral += coeff1*coeff2*KineticIntegral(pgb1,pgb2)
    end
  end
  return integral::Float64
end

function OverlapFundamental(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction)
  (K,P,γ) = GaussProductFundamental(pgb1,pgb2)
  # Overlap(s-type pgb1, s-type pgb2) (acc. to. Mathematica)
  return K*(π/γ)^(3/2)::Float64
end

function FIntegral(m::Integer,x::Real,APPROX_ZERO::Float64=1e-5)
  # F[m,x] = Integrate[u^2m Exp[-x u^2],{u,0,1}
  #         = 1/2 x^(-0.5-m) ( Gamma[1/2 + m] - Gamma[1/2 + m, x] ) # acc. to Mathematica
  x = max(x,APPROX_ZERO) # for x -> 0
  if (x<=APPROX_ZERO) return 1/(1+2*m) end
  return 1/2 * x^(-1/2-m) * ( GSL.sf_gamma(1/2+m) - GSL.sf_gamma_inc(1/2+m,x) )
end

function ASummand(
  f::Real,
  l1::Integer,
  l2::Integer,
  Ax::Real,
  Bx::Real,
  PCx::Real,
  γ::Real,
  l::Integer,
  r::Integer,
  i::Integer)
  # A[l1,l2,Ax,Bx,Cx,γ] = (-1)^l f_l(l1,l2,PAx,PBx) ((-1)^i l! PCx^(l-2r-2i) (1/(4γ))^(r+i)) / (r! i! (l-2r-2i)!)
  return (-1)^l * f * (-1)^i * factorial(l) * PCx^(l-2r-2i) * (1/(4γ))^(r+i) / (factorial(r) * factorial(i) * factorial(l - 2r - 2i))
end

function NuclearAttractionIntegral(
  pgb1::PrimitiveGaussianBasisFunction,
  pgb2::PrimitiveGaussianBasisFunction,
  atom::Atom)
  # V = K * A(l1,l2,Ax,Bx,Cx,γ) * A(m1,m2,Ay,By,Cy,γ) * A(n1,n2,Az,Bz,Cz,γ) * F[l+m+n-2(r+s+t) - (i+j+k),γ PC^2]
  #acc. to. Handbook of Comput. Quant. Chem. by Cook, chap. 7.7.3 final formula
  K,P,γ = GaussProductFundamental(pgb1,pgb2)
  C = atom.position

  result = 0
  for ((fx,l) in GaussProductPolynomialFactor(pgb1,pgb2).x)
    for (r in 0:floor(Int,(l/2)))
      for (i in 0:floor(Int,((l-2r)/2)))
	Ax = ASummand(fx,pgb1.mqn.x,pgb2.mqn.x,pgb1.center.x,pgb2.center.x,(P-C).x,γ,l,r,i)
	for ((fy,m) in GaussProductPolynomialFactor(pgb1,pgb2).y)
	  for (s in 0:floor(Int,(m/2)))
	    for (j in 0:floor(Int,((m-2s)/2)))
	      Ay = ASummand(fy,pgb1.mqn.y,pgb2.mqn.y,pgb1.center.y,pgb2.center.y,(P-C).y,γ,m,s,j)
	      for ((fz,n) in GaussProductPolynomialFactor(pgb1,pgb2).z)
		for (t in 0:floor(Int,(n/2)))
		  for (k in 0:floor(Int,((n-2t)/2)))
		    Az = ASummand(fz,pgb1.mqn.z,pgb2.mqn.z,pgb1.center.z,pgb2.center.z,(P-C).z,γ,n,t,k)
		    result += 2π/γ * K * Ax * Ay * Az * FIntegral(l+m+n-2*(r+s+t)-(i+j+k),γ*distance(P,C)^2)
		  end
		end
	      end
	    end
	  end
	end
      end
    end
  end
  
  return -atom.element.atomicNumber * result
end

function NuclearAttractionIntegral(
  cgb1::ContractedGaussianBasisFunction,
  cgb2::ContractedGaussianBasisFunction,
  atom::Atom)
  integral = 0.::Float64
  for (coeff1,pgb1) in zip(cgb1.coefficients,cgb1.primitiveBFs)
    for (coeff2,pgb2) in zip(cgb2.coefficients,cgb2.primitiveBFs)
      integral += coeff1*coeff2*NuclearAttractionIntegral(pgb1,pgb2,atom)
    end
  end
  return integral::Float64
end


type θfactors
  x::Array{Tuple{Float64,Int,Int},1} # θ,l,r
  y::Array{Tuple{Float64,Int,Int},1} # θ,l,r
  z::Array{Tuple{Float64,Int,Int},1} # θ,l,r
end

function θFactors(
  μ::PrimitiveGaussianBasisFunction,
  ν::PrimitiveGaussianBasisFunction)

  K,P,γ = IntegralsModule.GaussProductFundamental(μ,ν)

  factors = θfactors(Tuple{Float64,Int,Int}[],Tuple{Float64,Int,Int}[],Tuple{Float64,Int,Int}[])
  for (xyz in 1:3)
    sizehint!(getfield(factors,xyz),floor(Int,(length(getfield(GaussProductPolynomialFactor(μ,ν),xyz))+1)*5/8))
    for ((f,l) in getfield(IntegralsModule.GaussProductPolynomialFactor(μ,ν),xyz))
      for (r in 0:floor(Int,(l/2)))
	θ = f * (factorial(l)*γ^(r-l))/(factorial(r)*factorial(l-2r))
	push!(getfield(factors,xyz),(θ,l,r))
      end
    end
  end
  return factors
end

type Bfactors
  x::Array{Tuple{Float64,Int,Int,Int,Int,Int},1}	# B,l12,r12,i,l34,r34
  y::Array{Tuple{Float64,Int,Int,Int,Int,Int},1}	# B,l12,r12,i,l34,r34
  z::Array{Tuple{Float64,Int,Int,Int,Int,Int},1}	# B,l12,r12,i,l34,r34
end

function BFactors(
  μ::PrimitiveGaussianBasisFunction,
  ν::PrimitiveGaussianBasisFunction,
  λ::PrimitiveGaussianBasisFunction,
  σ::PrimitiveGaussianBasisFunction)

  K1,P,γ1 = IntegralsModule.GaussProductFundamental(μ,ν)
  K2,Q,γ2 = IntegralsModule.GaussProductFundamental(λ,σ)
  δ = 1/(4γ1) + 1/(4γ2)
  #p = (P-Q)	# this might be a typo in the book
  p = (Q-P)

  factors = Bfactors([],[],[])
  for (xyz in 1:3)
    for ((θ12,l12,r12) in getfield(θFactors(μ,ν),xyz))
      for ((θ34,l34,r34) in getfield(θFactors(λ,σ),xyz))
	#for (i in 0:floor(Integer,((l12-2r12)/2)))    # this might be a typo in the book (otherwise e.g. ERI(s,s,px,px2) != ERI(px,px2,s,s) (where the 2 denotes a second center moved by 0.5 in x direction)
	for (i in 0:floor(Int,((l12+l34-2r12-2r34)/2)))
	  B = (-1)^l34 * θ12 * θ34 * ((-1)^i*(2δ)^(2(r12+r34))*factorial(l12+l34-2r12-2r34)*δ^i*p.(xyz)^(l12+l34-2*(r12+r34+i)))/((4δ)^(l12+l34)*factorial(i)*factorial(l12+l34-2*(r12+r34+i)))
	  push!(getfield(factors,xyz),(B,l12,r12,i,l34,r34))
	end
      end
    end
  end
  return factors
end


function computeElectronRepulsionIntegral(
  μ::PrimitiveGaussianBasisFunction,
  ν::PrimitiveGaussianBasisFunction,
  λ::PrimitiveGaussianBasisFunction,
  σ::PrimitiveGaussianBasisFunction)
  # compute (μν|λσ) (Mulliken notation) = Integrate[μ(1) ν(1) 1/Abs(1-2) λ(2) σ(2), d1 d2]
  # in the most straightforward but primitive way (acc. to. Handbook of Comp. Quant. Chem. by Cook eq.7.1)
  A = μ.center
  B = ν.center
  C = λ.center
  D = σ.center
  α1 = μ.exponent
  α2 = ν.exponent
  α3 = λ.exponent
  α4 = σ.exponent
  K1,P,γ1 = IntegralsModule.GaussProductFundamental(μ,ν)
  K2,Q,γ2 = IntegralsModule.GaussProductFundamental(λ,σ)
  δ = 1/(4γ1) + 1/(4γ2)
  p = (P-Q)

  Bfactors = BFactors(μ,ν,λ,σ)
  Ω = 2π^2/(γ1 * γ2) * sqrt(π/(γ1 + γ2)) * exp(-α1*α2*distance(A,B)^2/γ1 - α3*α4*distance(C,D)^2/γ2)

  result = 0.::Float64
  for ((Bx,l12,r12,i,l34,r34) in Bfactors.x)
    for ((By,m12,s12,j,m34,s34) in Bfactors.y)
      for ((Bz,n12,t12,k,n34,t34) in Bfactors.z)
	V = (l12+l34+m12+m34+n12+n34) - 2*(r12+r34+s12+s34+t12+t34) - (i+j+k)
	result += Ω * Bx * By * Bz * IntegralsModule.FIntegral(V,distance(P,Q)^2/(4δ))
	#println("Bx*By*Bz*FIntegral[$V] = $Bx * $By * $Bz * $(IntegralsModule.FIntegral(V,distance(P,Q)^2/(4δ)))")
      end
    end
  end
  return result
end

function computeElectronRepulsionIntegral(
  μ::ContractedGaussianBasisFunction,
  ν::ContractedGaussianBasisFunction,
  λ::ContractedGaussianBasisFunction,
  σ::ContractedGaussianBasisFunction)

  integral::Float64 = 0.
  for (coeff1,pgb1) in zip(μ.coefficients,μ.primitiveBFs)
    for (coeff2,pgb2) in zip(ν.coefficients,ν.primitiveBFs)
      for (coeff3,pgb3) in zip(λ.coefficients,λ.primitiveBFs)
	for (coeff4,pgb4) in zip(σ.coefficients,σ.primitiveBFs)
	  integral += coeff1*coeff2*coeff3*coeff4*computeElectronRepulsionIntegral(pgb1,pgb2,pgb3,pgb4)
	end
      end
    end
  end
  return integral::Float64
end

function computeElectronRepulsionIntegral(μ::Shell,ν::Shell,λ::Shell,σ::Shell)
  [computeElectronRepulsionIntegral(μcgbf,νcgbf,λcgbf,σcgbf) for μcgbf in expandShell(μ), νcgbf in expandShell(ν), λcgbf in expandShell(λ), σcgbf in expandShell(σ)]
end

end # module
