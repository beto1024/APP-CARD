export type Role='ADMIN'|'STUDENT'
export type Rating='AGAIN'|'HARD'|'GOOD'|'EASY'
export interface Profile{id:string;email:string;display_name:string;role:Role}
export interface DueCard{id:string;kind:'WORD'|'VERB';level:'A1'|'A2'|'B1'|null;part_of_speech:string|null;german:string;spanish:string;conjugations:Record<string,string>|null;due_at:string|null;interval_days:number;ease_factor:number;repetitions:number;lapses:number}

