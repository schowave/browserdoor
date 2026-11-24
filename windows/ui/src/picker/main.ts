import { mount } from "svelte";
import "../lib/theme.css";
import Picker from "./Picker.svelte";

export default mount(Picker, { target: document.getElementById("app")! });
