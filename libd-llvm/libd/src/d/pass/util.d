module d.pass.util;

import d.ast.base;
import d.ast.expression;

import sdc.location;

private template Base(T) {
	static if(is(T : Expression)) {
		alias Expression Base;
	}
}

final class Deferred(T) if(is(Base!T == T)) : Base!T {
	private T cause;
	private Resolver!T resolver;
	
	this(Location location, T cause, Resolver!T resolver) {
		super(location);
		
		this.cause = cause;
		this.resolver = resolver;
	}
	
	T resolve() {
		if(resolver.test(this)) {
			return resolver.resolve(this);
		}
		
		return null;
	}
}

alias Deferred!Expression DeferredExpression;

private abstract class Resolver(T) if(is(Deferred!T)) {
	bool test(Deferred!T t);
	T resolve(Deferred!T t);
}

auto resolveOrDefer(alias test, alias resolve, T)(Location location, T t) if(!is(Base!T == T)) {
	return resolveOrDefer!(test, resolve, Base!T)(location, t);
}

auto resolveOrDefer(alias test, alias resolve, T)(Location location, T t) if(is(Deferred!T) && is(typeof(test(t)) == bool) && is(typeof(resolve(t)) : T)) {
	if(test(t)) {
		return resolve(t);
	}
	
	alias test testImpl;
	alias resolve resolveImpl;
	
	return new Deferred!T(location, t, new class() Resolver!T {
		override bool test(Deferred!T t) {
			return testImpl(t.cause);
		}
		
		override T resolve(Deferred!T t) {
			return resolveImpl(t.cause);
		}
	});
}

auto handleDeferredExpression(alias process, T)(Deferred!T t) if(is(typeof(process(T.init)) : T)) {
	class DeferedResolver : Resolver!T {
		override bool test(Deferred!T t) {
			auto defered = t;
			auto cause = t.cause;
			if(auto defCause = cast(Deferred!T) t.cause) {
				defCause.cause = process(defCause.cause);
				auto resolved = defCause.resolve();
				
				if(resolved) {
					t.cause = resolved;
				} else {
					return false;
				}
			}
			
			return true;
		}
		
		override T resolve(Deferred!T t) {
			return process(t.cause);
		}
	}
	
	auto resolved = t.resolve();
	
	// Avoid useless nesting :
	if(typeid({ return t.resolver; }()) is typeid(DeferedResolver)) {
		if(resolved) return resolved;
		
		return t;
	} else if(resolved) {
		return process(resolved);
	}
	
	t.cause = process(t.cause);
	resolved = t.resolve();
	
	if(resolved) {
		return process(resolved);
	}
	
	return new Deferred!T(t.location, t, new DeferedResolver());
}

