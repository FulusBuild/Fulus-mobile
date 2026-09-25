import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const url=Deno.env.get("SUPABASE_URL")!,key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{"content-type":"application/json"}});
Deno.serve(async(req)=>{
 if(req.method!=="GET")return json({error:{code:"METHOD_NOT_ALLOWED",message:"GET required"}},405);
 const h=req.headers.get("authorization");if(!h?.startsWith("Bearer "))return json({error:{code:"UNAUTHENTICATED",message:"Bearer token required"}},401);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});const {data:u,error:ue}=await db.auth.getUser(h.slice(7));if(ue||!u.user)return json({error:{code:"UNAUTHENTICATED",message:"Invalid access token"}},401);
 const q=new URL(req.url).searchParams,businessId=q.get("business_id"),locationId=q.get("location_id"),start=q.get("start"),end=q.get("end");
 if(!businessId||!start||!end)return json({error:{code:"INVALID_REPORT_REQUEST",message:"business_id, start and end are required"}},400);
 const from=new Date(start),to=new Date(end);if(Number.isNaN(from.getTime())||Number.isNaN(to.getTime())||to<from)return json({error:{code:"INVALID_REPORT_PERIOD",message:"Invalid report period"}},400);
 const {data:m}=await db.from("business_memberships").select("role_id,status,roles(name)").eq("business_id",businessId).eq("user_id",u.user.id).eq("status","active").maybeSingle();if(!m)return json({error:{code:"FORBIDDEN",message:"User is not an active member of this business"}},403);
 const role=Array.isArray(m.roles)?m.roles[0]:m.roles;
 const isBusinessAdmin=role?.name==="owner"||role?.name==="admin";
 const {data:locationRows,error:locationError}=await db.from("location_memberships").select("location_id").eq("business_id",businessId).eq("user_id",u.user.id).eq("status","active");
 if(locationError)return json({error:{code:"LOCATION_MEMBERSHIP_LOOKUP_FAILED",message:"Unable to resolve location access"}},500);
 const accessibleLocationIds=new Set((locationRows??[]).map(row=>String(row.location_id)));
 if(isBusinessAdmin){
   const {data:businessLocations,error:businessLocationsError}=await db.from("locations").select("id").eq("business_id",businessId).eq("status","active");
   if(businessLocationsError)return json({error:{code:"LOCATION_LOOKUP_FAILED",message:"Unable to resolve business locations"}},500);
   for(const location of businessLocations??[])accessibleLocationIds.add(String(location.id));
 }
 if(locationId){
   if(!accessibleLocationIds.has(String(locationId)))return json({error:{code:"FORBIDDEN",message:"User is not authorized for this location"}},403);
 }else if(!isBusinessAdmin){
   return json({error:{code:"LOCATION_REQUIRED",message:"A location_id is required for non-admin cloud reports"}},403);
 }
 const device=q.get("device_id");if(!device)return json({error:{code:"DEVICE_REQUIRED",message:"device_id is required for cloud reports"}},400);const {data:d}=await db.from("devices").select("status").eq("business_id",businessId).eq("device_client_id",device).maybeSingle();if(!d||d.status!=="active")return json({error:{code:"DEVICE_NOT_REGISTERED",message:"Device is not registered or active"}},403);
 let sq=db.from("sales").select("id,total,discount,tax,amount_paid,payment_method,sale_date").eq("business_id",businessId).is("deleted_at",null).gte("sale_date",from.toISOString()).lte("sale_date",to.toISOString());if(locationId)sq=sq.eq("location_id",locationId);
 const {data:sales,error:se}=await sq;if(se)return json({error:{code:"REPORT_QUERY_FAILED",message:"Unable to load sales report"}},500);const sr=sales??[];
 const ids=sr.map(s=>s.id);let items:any[]=[];if(ids.length){const x=await db.from("sale_items").select("sale_id,product_id,quantity,line_total").in("sale_id",ids);if(x.error)return json({error:{code:"REPORT_QUERY_FAILED",message:"Unable to load sales items"}},500);items=x.data??[];}
 const pids=[...new Set(items.map(i=>i.product_id).filter(Boolean))];let prods:any[]=[];if(pids.length){const x=await db.from("products").select("id,name").in("id",pids);prods=x.data??[];}const pn=new Map(prods.map(p=>[p.id,p.name]));const top=new Map<string,{product_id:string,name:string,quantity:number,revenue:number}>();
 for(const i of items){if(!i.product_id)continue;const v=top.get(i.product_id)??{product_id:i.product_id,name:pn.get(i.product_id)??"Unknown",quantity:0,revenue:0};v.quantity+=Number(i.quantity??0);v.revenue+=Number(i.line_total??0);top.set(i.product_id,v);}
 const payment:any={};for(const s of sr){const k=s.payment_method??"unknown";payment[k]=(payment[k]??0)+Number(s.amount_paid??0);}
 let eq=db.from("expenses").select("amount,category").eq("business_id",businessId).is("deleted_at",null).gte("expense_date",from.toISOString()).lte("expense_date",to.toISOString());if(locationId)eq=eq.eq("location_id",locationId);const {data:ex,error:ee}=await eq;if(ee)return json({error:{code:"REPORT_QUERY_FAILED",message:"Unable to load expense report"}},500);const er=ex??[];const expenseTotal=er.reduce((a,e)=>a+Number(e.amount??0),0),cat:any={};for(const e of er){const k=e.category??"Uncategorized";cat[k]=(cat[k]??0)+Number(e.amount??0);}
 const {data:cr,error:ce}=await db.from("customers").select("id,name,outstanding_balance,created_at").eq("business_id",businessId).eq("is_active",true);if(ce)return json({error:{code:"REPORT_QUERY_FAILED",message:"Unable to load customer report"}},500);const customers=cr??[];
 let stock:any[]=[];if(locationId){const x=await db.from("product_stock_levels").select("product_id,current_stock").eq("location_id",locationId);stock=x.data??[];}const stockMap=new Map(stock.map(s=>[s.product_id,Number(s.current_stock??0)]));
 const {data:activeProducts}=await db.from("products").select("id,name,cost_price,low_stock_threshold").eq("business_id",businessId).eq("is_active",true).is("deleted_at",null);const inv=(activeProducts??[]).map(p=>{const qty=stockMap.get(p.id)??0;return{product_id:p.id,name:p.name,current_stock:qty,stock_value:Number(p.cost_price??0)*qty,low_stock:qty>0&&qty<=Number(p.low_stock_threshold??0),out_of_stock:qty<=0};});
 const revenue=sr.reduce((a,s)=>a+Number(s.total??0),0),discounts=sr.reduce((a,s)=>a+Number(s.discount??0),0),tax=sr.reduce((a,s)=>a+Number(s.tax??0),0),outstanding=customers.reduce((a,c)=>a+Number(c.outstanding_balance??0),0),newCustomers=customers.filter(c=>{const d=new Date(c.created_at);return d>=from&&d<=to}).length;
 let cq=db.from("cash_ledger").select("amount,direction").eq("business_id",businessId).gte("created_at",from.toISOString()).lte("created_at",to.toISOString());if(locationId)cq=cq.eq("location_id",locationId);const {data:cash}=await cq;const inflow=(cash??[]).filter(c=>c.direction==="in").reduce((a,c)=>a+Number(c.amount??0),0),outflow=(cash??[]).filter(c=>c.direction==="out").reduce((a,c)=>a+Number(c.amount??0),0);
 return json({data:{period:{start:from.toISOString(),end:to.toISOString()},sales:{revenue,sales_count:sr.length,total_discount:discounts,total_tax:tax,by_payment_method:payment,top_products:[...top.values()].sort((a,b)=>b.revenue-a.revenue).slice(0,10)},inventory:{total_products:inv.length,total_stock_value:inv.reduce((a,p)=>a+p.stock_value,0),low_stock_count:inv.filter(p=>p.low_stock).length,out_of_stock_count:inv.filter(p=>p.out_of_stock).length,items:inv},customers:{outstanding_credit:outstanding,new_customers:newCustomers,top_customers:customers.map(c=>({customer_id:c.id,customer_name:c.name,outstanding_balance:Number(c.outstanding_balance??0)})).sort((a,b)=>b.outstanding_balance-a.outstanding_balance).slice(0,10)},finance:{revenue,expenses:expenseTotal,net_profit:revenue-expenseTotal,expense_breakdown:Object.entries(cat).map(([category,total])=>({category,total}))},cash_flow:{inflow,outflow,net_cash_flow:inflow-outflow},server_authoritative:true}});
});