module Interpreter where

import Control.Monad

import Data.Map (Map)
import qualified Data.Map as Map

import CPP.Abs
import CPP.Print
import CPP.ErrM

type Env = (Sig, [Context])
type Sig = Map Id Def
type Context = Map Id Val

data Val 
	= I Integer 
	| D Double 
	| B Bool 
	| Void 
	deriving (Eq, Show, Ord, Read)


interpret :: Program -> IO ()
interpret (PDefs (defs)) = do 
	env <- addFuns' emptyEnv defs
	(DFun _ id args stms) <- lookupFun env (Id "main")
	execStms env stms
	return ()

execStms :: Env -> [Stm] -> IO Env
execStms env [] = return env
execStms env (stm:stms) = do
	env1 <- execStm env stm
	execStms env1 stms 

-- Adds builtin functions to prevent the names being used again by a user function.
addFuns' :: Env -> [Def] -> IO Env
addFuns' env defs = do 
	env1 <- addFun env (DFun Type_int (Id "readInt") [] [])
	env2 <- addFun env1 (DFun Type_double (Id "readDouble") [] [])
	env3 <- addFun env2 (DFun Type_void (Id "printInt") ((ADecl (Type_int) (Id "a")):[]) [])
	env4 <- addFun env3 (DFun Type_void (Id "printDouble") ((ADecl (Type_double) (Id "a")):[]) [])
	addFuns env4 defs

addFuns :: Env -> [Def] -> IO Env
addFuns env [] = return env
addFuns env ((DFun t id args stms):defs) = do
	env1 <- addFun env (DFun t id args stms)
	addFuns env1 defs


execStm :: Env -> Stm -> IO Env
execStm env stm = case stm of
	SExp exp -> do
		(_, env) <- evalExp env exp
		return env
	SDecls t ids -> addDecls env ids
	SInit t id exp -> do
		(val, env1) <- evalExp env exp
		addVar env1 id val
	SReturn exp -> do
		(_, env1) <- evalExp env exp
		return env1
	SWhile exp stm -> do
		(B bool, env1) <- evalExp env exp
		if bool then do
			env2 <- execStm (newBlock env1) stm
			execStm (exitBlock env2) (SWhile exp stm)
		else return env1
	SBlock stms -> do
		env2 <- execBlock (newBlock env) stms
		return (exitBlock env2)
	SIfElse exp stm1 stm2 -> do
		(B bool, env1) <- evalExp env exp
		if bool then do
			env2 <- execStm (newBlock env1) stm1
			return (exitBlock env2)
		else do 
			env2 <- execStm (newBlock env1) stm2
			return (exitBlock env2)

addDecls :: Env -> [Id] -> IO Env
addDecls env [] = return env
addDecls env (id:ids) = do
	env1 <- addVar env id Void
	addDecls env1 ids

execBlock :: Env -> [Stm] -> IO Env
execBlock env [] 	   = return env
execBlock env (stm:stms) = do
	env1 <- execStm env stm
	execBlock env1 stms

evalFun :: Env -> [Stm] -> IO (Val, Env)
evalFun (sig, c:con) [] = return (Void, (sig, con))
evalFun env (stm:stms) = case stm of 
	SReturn exp -> do
		(val, env1) <- evalExp env exp
		return (val, (exitBlock env1))
	otherwise -> do
		newEnv <- execStm env stm
		evalFun newEnv stms

evalExp :: Env -> Exp -> IO (Val, Env)
evalExp env exp = case exp of
	ETrue -> return (B True, env)
	EFalse -> return (B False, env)
	EInt i -> return ((I i), env)
	EDouble d -> return ((D d), env)
	EId id -> do 
		val <- lookupVar env id
		return (val, env)
	EApp id exps -> case id of 
		(Id "printInt") -> do 
			(val, env1) <- evalExp env exp 
			print val
			return (Void, env1)
		(Id "printDouble") -> do
			(val, env1) <- evalExp env exp 
			print val
			return (Void, env1)
		(Id "readInt") -> do 
			string <- getLine
			return ((I (read string)), env)
		(Id "readDouble") -> do 
			string <- getLine
			return ((D (read string)), env)
		otherwise -> do
			(DFun t id2 args stms) <- lookupFun env id
			env1 <- mapArgsToVals (newBlock env) args exps
			evalFun env1 stms
	EPostIncr id -> do
		val <- lookupVar env id
		case val of
			D d -> do 
				newEnv <- extendVar env id (D (d + 1))
				return (val, newEnv)
			I i -> do 
				newEnv <- extendVar env id (I (i + 1))
				return (val, newEnv)
			otherwise -> fail "Cant increment this type"
	EPostDecr id -> do
		val <- lookupVar env id
		case val of
			D d -> do 
				newEnv <- extendVar env id (D (d - 1))
				return (val, newEnv)
			I i -> do 
				newEnv <- extendVar env id (I (i - 1))
				return (val, newEnv)
			otherwise -> fail "Cant decrement this type"
	EPreIncr id -> do
		val <- lookupVar env id
		case val of
			D d -> do 
				newEnv <- extendVar env id (D (d + 1))
				return (D (d + 1), newEnv)
			I i -> do 
				newEnv <- extendVar env id (I (i + 1))
				return (I (i + 1), newEnv)
			otherwise -> fail "Cant increment this type"
	EPreDecr id -> do
		val <- lookupVar env id
		case val of
			D d -> do 
				newEnv <- extendVar env id (D (d - 1))
				return (D (d - 1), newEnv)
			I i -> do 
				newEnv <- extendVar env id (I (i - 1))
				return (I (i - 1), newEnv)
			otherwise -> fail "Cant decrement this type"
	EDiv exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		case (val1, val2) of
			(I val11, I val12) -> 
				if val12 == 0 then
				fail "Division by zero is not allowed"
				else return (I (val11 `div` val12), newEnv2)
			(D val11, D val12) -> 
				if val12 == 0 then
				fail "Division by zero is not allowed"
				else return (D (val11 / val12), newEnv2)
			otherwise -> fail "Cannot divide this type."
		
	ETimes exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		case (val1, val2) of
			(I val11, I val12) -> 
				return (I (val11 * val12), newEnv2)
			(D val11, D val12) -> 
				return (D (val11 * val12), newEnv2)
			otherwise -> fail "Cannot multiply this type."
	EPlus exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		case (val1, val2) of
			(I val11, I val12) -> 
				return (I (val11 + val12), newEnv2)
			(D val11, D val12) -> 
				return (D (val11 + val12), newEnv2)
			otherwise -> fail "Cannot add this type."
	EMinus exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		case (val1, val2) of
			(I val11, I val12) -> 
				return (I (val11 - val12), newEnv2)
			(D val11, D val12) -> 
				return (D (val11 - val12), newEnv2)
			otherwise -> fail "Cannot subtract this type."
	ELt exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((<) val1 val2), newEnv2)
	EGt exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((>) val1 val2), newEnv2)
	ELtEq exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((<=) val1 val2), newEnv2)
	EGtEq exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((>=) val1 val2), newEnv2)
	EEq exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((==) val1 val2), newEnv2)
	ENEq exp1 exp2 -> do
		(val1, newEnv1) <- evalExp env exp1
		(val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((/=) val1 val2), newEnv2)
	EAnd exp1 exp2 -> do
		(B val1, newEnv1) <- evalExp env exp1
		(B val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((&&) val1 val2), newEnv2)
	EOr exp1 exp2 -> do
		(B val1, newEnv1) <- evalExp env exp1
		(B val2, newEnv2) <- evalExp newEnv1 exp2
		return (B ((||) val1 val2), newEnv2)
	EAss id exp -> do
		(val, env1) <- evalExp env exp
		env2 <- extendVar env1 id val
		return (val, env2)

-- assumes that [Arg] and [Exp] have the same length, 
-- typechecker should catch it otherwise.
mapArgsToVals :: Env -> [Arg] -> [Exp] -> IO Env
mapArgsToVals env [] [] = return env
mapArgsToVals env ((ADecl t id):args) (exp:exps) = do
				(val, env1) <- evalExp env exp
				updatedEnv <- addVar env1 id val
				mapArgsToVals updatedEnv args exps
							


-- binEvalNum :: Env -> Exp -> Exp -> (Num -> Num -> Num) -> IO (Val, Env)
-- binEvalNum env exp1 exp2 op = do
-- 		(val1, newEnv1) <- evalExp env exp1
-- 		(val2, newEnv2) <- evalExp newEnv1 exp2
-- 		return ((op val1 val2), newEnv2)
-- 
-- binEvalBool :: Env -> Exp -> Exp -> (Bool -> Bool -> Bool) -> IO (Val, Env)
-- binEvalBool env exp1 exp2 op = do
-- 		(val1, newEnv1) <- evalExp env exp1
-- 		(val2, newEnv2) <- evalExp newEnv1 exp2
-- 		return ((op val1 val2), newEnv2)

lookupVar :: Env -> Id -> IO Val
lookupVar (sig, []) id = fail ((show id) ++ " not declared")
lookupVar (sig, c:con) id = case Map.lookup id c of
	Just val -> return val
	Nothing -> do 
		val <- lookupVar (sig, con) id
		return val

lookupFun :: Env -> Id -> IO Def
lookupFun (sig, con) id = case Map.lookup id sig of
	Just def -> return def
	Nothing -> fail ("There is no function by the name " ++ (show id))

extendVar :: Env -> Id -> Val -> IO Env
extendVar (sig, []) id val = fail ("Cannot assign value " ++ (show val) ++ " to variable " ++ (show id) ++ " because it does not exist.")
extendVar (sig, c:con) id val = case Map.lookup id c of
	Just _ -> return (sig, (Map.insert id val c):con)
	Nothing -> do 
		(sig1, con1) <- extendVar (sig, con) id val
		return (sig1, (c:con1))


addFun :: Env -> Def -> IO Env
addFun (sig, con) (DFun t id args stms) = case Map.lookup id sig of
	Just _ -> fail ("Function " ++ (show id) ++ " is already declared.")
	Nothing -> return ((Map.insert id (DFun t id args stms) sig), con)

addVar :: Env -> Id -> Val -> IO Env
addVar (sig, []) id val = fail "fail addvar"
addVar (sig, c:con) id val = case Map.lookup id c of
	Just _ -> fail ("Variable " ++ (show id) ++ " is already declared.")
	Nothing -> return (sig, (Map.insert id val c):con)

newBlock :: Env -> Env
newBlock (sig, con) = (sig, Map.empty:con)

exitBlock :: Env -> Env
exitBlock (sig, c:con) = (sig, con)

emptyEnv :: Env
emptyEnv = (Map.empty, [])
