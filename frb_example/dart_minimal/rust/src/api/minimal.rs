use flutter_rust_bridge::frb;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn minimal_adder(a: i32, b: i32) -> i32 {
    a + b
}


pub async fn sleep_fn( sleep_cb: impl Fn(i32) -> flutter_rust_bridge::DartFnFuture<()> + Send + Sync + 'static,){
    tokio::select!{
        _=(sleep_cb)(1000)=>{
            println!("sleep 1000 returning")
        }
        _=(sleep_cb)(500)=>{
            println!("sleep 500 returning")
        }
    }
}