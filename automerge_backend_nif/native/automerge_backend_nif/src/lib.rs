use std::mem::drop;
use std::sync::Mutex;
use std::sync::MutexGuard;
use std::vec::Vec;
use std::convert::TryInto;

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::json;
use serde_rustler::{to_term, Deserializer};
use serde_transcode::transcode;

use rustler::{Encoder, Env, Error, NifResult, ResourceArc, Term};

use automerge_backend::{Backend, Change};
use automerge_protocol::{ChangeHash, Patch, UncompressedChange};

struct Wrapper {
    heads: Vec<Vec<u8>>,
    backend: Backend,
    frozen: bool,
}

impl Wrapper {
    fn set_heads(&mut self, heads: Vec<Vec<u8>>) {
        self.heads = heads;
    }

    pub fn set_backend(&mut self, backend: Backend) {
        self.backend = backend;
    }

    fn set_frozen(&mut self, frozen: bool) {
        self.frozen = frozen;
    }
}

struct State {
    mutex: Mutex<Wrapper>,
}

type StateArc = ResourceArc<State>;

mod atoms {
    rustler::rustler_atoms! {
      atom ok;
      atom error;
    }
}

fn elixir_to_rust<T: DeserializeOwned>(value: &Term) -> serde_json::error::Result<T> {
    let de = Deserializer::from(*value);

    let mut ser_vec = Vec::new();
    let mut ser = serde_json::Serializer::new(&mut ser_vec);
    transcode(de, &mut ser).map_err(|_err| "Unable to transcode");

    serde_json::from_slice(ser_vec.as_slice())
}

fn rust_to_elixir<T: Serialize>(
    env: Env,
    value: T,
) -> std::result::Result<rustler::Term, rustler::Error> {
    let ser = serde_rustler::Serializer::from(env);
    let de = json!(value);

    serde_transcode::transcode(de, ser)
        .map_err(|_err| Error::Atom("Unable to encode to erlang terms"))
}

fn apply_changes<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let (new_wrapper, result) = get_mut_state(&state, |backend| {
        let changes: Vec<Vec<u8>> = args[1].decode()?;

        let mut ch = Vec::with_capacity(changes.len());
        for c in changes.iter() {
            ch.push(Change::from_bytes(c.to_vec()).unwrap());
        }

        let patches = backend.apply_changes(ch).unwrap();

        Ok(patches)
    })?;

    let new_state = ResourceArc::new(State{mutex: Mutex::new(new_wrapper)});

    Ok((new_state.encode(env), rust_to_elixir(env, result)?).encode(env))
}

fn apply_local_change<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let (new_wrapper, (patch, encoded_change)) = get_mut_state(&state, |backend| {
        return match elixir_to_rust(&args[1]) {
            Ok(change) => match backend.apply_local_change(change) {
                Ok((patch, change)) => {
                    let result: Vec<u8> = change.raw_bytes().into();

                    Ok((patch, result))
                },
                Err(message) => Err(Error::RaiseTerm(Box::new(format!("{}", message)))),
            },
            Err(message) => Err(Error::RaiseTerm(Box::new(format!("{}", message)))),
        };
    })?;

    let new_state = ResourceArc::new(State{mutex: Mutex::new(new_wrapper)});

    Ok((new_state, rust_to_elixir(env, patch)?, encoded_change).encode(env))
}

fn load_changes<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let (new_wrapper, _result) = get_mut_state(&state, |backend| {
        let changes: Vec<Vec<u8>> = args[1].decode()?;

        let mut ch = Vec::with_capacity(changes.len() as usize);
        for c in changes.iter() {
            ch.push(Change::from_bytes(c.to_vec()).unwrap());
        }

        return match backend.load_changes(ch) {
            Ok(()) => Ok(()),
            Err(message) => Err(Error::RaiseTerm(Box::new(format!("{}", message)))),
        };
    })?;

    let new_state = ResourceArc::new(State{mutex: Mutex::new(new_wrapper)});

    Ok(new_state.encode(env))
}

fn get_patch<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let resp = get_state(&state, |backend| {
        let patch: Patch = backend.get_patch().unwrap();

        Ok(patch)
    })?;

    rust_to_elixir(env, resp)
}

fn get_heads<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;
    let wrapper = state.mutex.lock().unwrap();

    Ok(wrapper.heads.encode(env))
}

fn get_all_changes<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;
    let deps: Vec<ChangeHash> = vec![];

    let resp = get_state(&state, |backend| {
        let changes: Vec<&Change> = backend.get_changes(&deps);

        let mut result: Vec<Vec<u8>> = Vec::new();
        for c in changes {
            result.push(c.raw_bytes().iter().cloned().collect());
        }

        Ok(result)
    })?;

    to_term(env, resp).map_err(|err| err.into())
}

fn get_changes<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;
    let have_deps: Vec<Vec<u8>> = args[1].decode()?;
    let mut deps: Vec<ChangeHash> = vec![];

    for dep in have_deps.into_iter() {
        deps.push(dep.as_slice().try_into().unwrap())
    }

    let resp = get_state(&state, |backend| {
        let changes: Vec<&Change> = backend.get_changes(&deps);

        let mut result: Vec<Vec<u8>> = Vec::new();
        for c in changes {
            result.push(c.raw_bytes().iter().cloned().collect());
        }

        Ok(result)
    })?;

    to_term(env, resp).map_err(|err| err.into())
}

fn get_missing_deps<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let resp = get_state(&state, |backend| Ok(backend.get_missing_deps()))?;

    to_term(env, resp).map_err(|err| err.into())
}

fn free<'a>(_env: Env<'a>, args: &[Term<'a>]) -> Result<(), Error>{
    let state: StateArc = args[0].decode()?;
    let wrapper = &mut get_wrapper(&state)?;

    wrapper.set_frozen(true);
    wrapper.set_backend(Backend::init());
    wrapper.set_heads(vec![]);

    Ok(())
}

fn clone<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;
    let wrapper = &mut get_wrapper(&state)?;

    let new_wrapper = Wrapper{frozen: false, backend: wrapper.backend.clone(), heads: wrapper.heads.clone()};

    let new_state = ResourceArc::new(State{mutex: Mutex::new(new_wrapper)});

    Ok(new_state.encode(env))
}

fn init<'a>(env: Env<'a>, _args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let wrapper = Wrapper {
        backend: Backend::init(),
        frozen: false,
        heads: vec![],
    };

    let out: StateArc = ResourceArc::new(State {
        mutex: Mutex::new(wrapper),
    });

    Ok(out.encode(env))
}

fn load<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let doc: Vec<u8> = args[0].decode()?;

    let backend: Backend = Backend::load(doc).unwrap();
    let wrapper = Wrapper {
        backend: backend,
        frozen: false,
        heads: vec![],
    };
    let out: StateArc = ResourceArc::new(State {
        mutex: Mutex::new(wrapper),
    });

    Ok(out.encode(env))
}

fn save<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let state: StateArc = args[0].decode()?;

    let resp = get_state(&state, |backend| {
        let out: Vec<u8> = backend.save().unwrap();

        Ok(out)
    })?;

    to_term(env, resp).map_err(|err| err.into())
}

fn encode_change<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let uncompressed_change: UncompressedChange = elixir_to_rust(&args[0]).unwrap();
    let change: Change = Change::from(uncompressed_change);

    to_term(env, change.raw_bytes()).map_err(|err| err.into())
}

fn decode_change<'a>(env: Env<'a>, args: &[Term<'a>]) -> NifResult<Term<'a>> {
    let encoded_change: Vec<u8> = args[0].decode()?;
    let change: Change = Change::from_bytes(encoded_change).unwrap();

    let uncompressed_change: UncompressedChange = change.decode();

    rust_to_elixir(env, uncompressed_change)
}

fn get_mut_state<F, T>(state: &StateArc, action: F) -> Result<(Wrapper, T), Error>
where
    F: Fn(&mut Backend) -> Result<T, Error>,
    T: Serialize,
{
    let wrapper = &mut get_wrapper(state)?;

    match action(&mut wrapper.backend) {
        Ok(result) => {
            let heads = &wrapper.backend.get_heads();

            let resp: Vec<Vec<u8>> = heads.iter().map(|head| head.0.to_vec()).collect();

            let new_wrapper = Wrapper {
                backend: wrapper.backend.clone(),
                frozen: false,
                heads: resp,
            };

            wrapper.set_frozen(true);

            Ok((new_wrapper, result))
        }
        Err(err) => Err(err),
    }
}

fn get_state<F, T>(state: &StateArc, action: F) -> Result<T, Error>
where
    F: Fn(&Backend) -> Result<T, Error>,
    T: Serialize,
{
    let wrapper = &get_wrapper(state)?;

    let result = action(&wrapper.backend);
    drop(wrapper);

    result
}

fn get_wrapper(state: &StateArc) -> Result<MutexGuard<Wrapper>, Error> {
    let wrapper = state.mutex.lock().unwrap();

    if wrapper.frozen {
        Err(Error::RaiseAtom("frozen"))
    } else {
        Ok(wrapper)
    }
}

rustler::rustler_export_nifs! {
  "Elixir.Automerge.Backend.NIF",
  [
    ("apply_changes", 2, apply_changes),
    ("apply_local_change", 2, apply_local_change),
    ("load_changes", 2, load_changes),
    ("get_patch", 1, get_patch),
    ("get_heads", 1, get_heads),
    ("get_changes", 2, get_changes),
    ("get_all_changes", 1, get_all_changes),
    ("get_missing_deps", 1, get_missing_deps),
    ("init", 0, init),
    ("free", 1, free),
    ("load", 1, load),
    ("save", 1, save),
    ("clone", 1, clone),
    ("encode_change", 1, encode_change),
    ("decode_change", 1, decode_change),
  ],
  Some(|env: Env, _| {
        rustler::resource_struct_init!(State, env);
        true
    })
}
