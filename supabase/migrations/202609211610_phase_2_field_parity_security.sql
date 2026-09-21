revoke all on function public.create_customer(uuid,text,text,text,text,numeric,text)
  from public, anon, authenticated;
revoke all on function public.record_expense(uuid,uuid,numeric,text,text,text,uuid,text)
  from public, anon, authenticated;
grant execute on function public.create_customer(uuid,text,text,text,text,numeric,text)
  to service_role;
grant execute on function public.record_expense(uuid,uuid,numeric,text,text,text,uuid,text)
  to service_role;

revoke all on table public.expense_categories from anon, authenticated;
grant select, insert, update, delete on table public.expense_categories to service_role;
