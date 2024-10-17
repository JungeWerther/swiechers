
type NullableRecord<U extends Record<string, any>> = {
    [K in keyof U]: U[K] | null;
} 

export function Depends<T, U extends Record<string, any>>(
    nullable: T | null, 
    expr: () => U 
): NullableRecord<U> {
    return nullable ? expr() : new Proxy({} as U, {
        get: () => null
    })}

     


